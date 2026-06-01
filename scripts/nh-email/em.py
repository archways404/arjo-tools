import csv
import re
from datetime import datetime
from html.parser import HTMLParser

import pypff

results = {}


class HTMLStripper(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.skip = False

    def handle_starttag(self, tag, attrs):
        if tag.lower() in ("style", "script"):
            self.skip = True

    def handle_endtag(self, tag):
        if tag.lower() in ("style", "script"):
            self.skip = False

    def handle_data(self, d):
        if not self.skip:
            self.text.append(d)

    def get_text(self):
        return "".join(self.text)


def strip_html(html_content):
    s = HTMLStripper()
    s.feed(html_content)
    return s.get_text()


def parse_folder(folder):
    for i in range(folder.get_number_of_sub_folders()):
        parse_folder(folder.get_sub_folder(i))
    for i in range(folder.get_number_of_sub_messages()):
        msg = folder.get_sub_message(i)
        try:
            body = (
                msg.html_body.decode("utf-8", errors="ignore") if msg.html_body else ""
            )
            body = strip_html(body)
            received = msg.delivery_time

            inc_match = re.search(r"Incident Number:\s+(INC\d+)", body, re.IGNORECASE)
            if not inc_match:
                continue
            incident_number = inc_match.group(1)

            hire_match = re.search(
                r"Hire Date:\s*(\d{4}-\d{2}-\d{2})", body, re.IGNORECASE
            )
            if not hire_match:
                continue

            hire_date = datetime.strptime(hire_match.group(1), "%Y-%m-%d")
            days_until_hire = (
                (hire_date - received.replace(tzinfo=None)).days if received else ""
            )

            # Deduplicate — keep first occurrence per INC number
            if incident_number not in results:
                results[incident_number] = {
                    "Incident Number": incident_number,
                    "Received Date": received.strftime("%Y-%m-%d") if received else "",
                    "Hire Date": hire_match.group(1),
                    "Days Until Hire": days_until_hire,
                }

        except Exception as e:
            print(f"Error parsing message {i}: {e}")


pst = pypff.file()
pst.open(r"C:\Users\un024247\Downloads\email-nh-export-copy.pst")
root = pst.get_root_folder()
parse_folder(root)

with open("new_hires.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=["Incident Number", "Received Date", "Hire Date", "Days Until Hire"],
    )
    writer.writeheader()
    writer.writerows(results.values())

print(f"Done — {len(results)} unique incidents parsed, saved to new_hires.csv")
