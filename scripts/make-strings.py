# -*- coding: utf-8 -*-
"""Writes SnapBar/Resources/Localizable.xcstrings (English source, Hebrew translation).

Run after a build: it reads the keys Xcode extracted (.stringsdata) and fails if any key
has no Hebrew, so a new string in the UI can never ship untranslated.

    python3 scripts/make-strings.py
"""
import glob
import json
import os
import sys

HE = {
    "A panel that waits for you": "חלונית שמחכה לך",
    "About SnapBar": "אודות SnapBar",
    "Actual Size": "גודל אמיתי",
    "Add to Favorites": "הוסף למועדפים",
    "Add ⌘, ⌃ or ⌥ to the key.": "צריך להוסיף ⌘, ⌃ או ⌥ למקש.",
    "Advanced": "מתקדם",
    "After 1 minute": "אחרי דקה",
    "After 10 seconds": "אחרי 10 שניות",
    "After 30 days": "אחרי 30 ימים",
    "After 30 seconds": "אחרי 30 שניות",
    "After 5 seconds": "אחרי 5 שניות",
    "After 7 days": "אחרי 7 ימים",
    "After 90 days": "אחרי 90 ימים",
    "After a year": "אחרי שנה",
    "All Screenshots": "כל הצילומים",
    "Allow Notifications": "אפשר התראות",
    "Allow screen recording": "אישור הקלטת מסך",
    "Allowed": "מאושר",
    "Allow…": "אפשר…",
    "Another app already uses this shortcut.": "אפליקציה אחרת כבר משתמשת בקיצור הזה.",
    "Apps": "אפליקציות",
    "Apps appear after your first screenshots": "האפליקציות יופיעו כאן אחרי הצילומים הראשונים",
    "Arrow": "חץ",
    "Back": "חזרה",
    "Blur": "טשטוש",
    "Bottom left": "למטה משמאל",
    "Bottom right": "למטה מימין",
    "Cancel": "ביטול",
    "Capture Area": "צלם אזור",
    "Capture Full Screen": "צלם מסך מלא",
    "Capture Window": "צלם חלון",
    "Capture a window": "צילום חלון",
    "Capture an area": "צילום אזור",
    "Capture the full screen": "צילום מסך מלא",
    "Choose": "בחר",
    "Choose…": "בחר…",
    "Clear": "נקה",
    "Click a shortcut, then press the new keys. Esc cancels and Delete clears it. ⇧⌘4 keeps working as usual.":
        "לוחצים על קיצור ואז על המקשים החדשים. Esc מבטל ו-Delete מנקה. ⇧⌘4 ממשיך לעבוד כרגיל.",
    "Close": "סגור",
    "Close without saving?": "לסגור בלי לשמור?",
    "Continue": "המשך",
    "Copy": "העתק",
    "Copy Path": "העתק נתיב",
    "Copy Text": "העתק טקסט",
    "Copy them to the clipboard and library too": "להעתיק גם אותם ללוח ולספרייה",
    "Corner": "פינה",
    "Crop": "חיתוך",
    "Custom Range": "טווח מותאם",
    "Cut": "גזור",
    "Dates": "תאריכים",
    "Drag into any app": "אפשר לגרור לכל אפליקציה",
    "Edit": "ערוך",
    "Ellipse": "אליפסה",
    "Every screenshot in one place": "כל הצילומים במקום אחד",
    "Every screenshot lands on the clipboard and in one tidy folder at the same time.":
        "כל צילום נכנס ללוח וגם לתיקייה מסודרת אחת, באותו רגע.",
    "Export": "ייצוא",
    "Export as JPEG…": "ייצוא כ-JPEG…",
    "Export…": "ייצוא…",
    "Favorite": "מועדף",
    "Favorites": "מועדפים",
    "Favorites are always kept.": "מועדפים נשמרים תמיד.",
    "File": "קובץ",
    "Files": "קבצים",
    "Filter by date, by app, or by words that appear inside the picture.":
        "סינון לפי תאריך, לפי אפליקציה או לפי מילים שמופיעות בתוך התמונה.",
    "From": "מתאריך",
    "General": "כללי",
    "Halves the pixel size so files are smaller. Leave it off for full sharpness.":
        "מקטין את התמונה לחצי כדי שהקבצים יהיו קטנים יותר. כשזה כבוי, החדות מלאה.",
    "Help": "עזרה",
    "Hide SnapBar": "הסתר את SnapBar",
    "Hide automatically": "הסתרה אוטומטית",
    "Highlighter": "מרקר",
    "If it stays off after you allow it, quit SnapBar and open it again.":
        "אם זה נשאר כבוי אחרי האישור, צריך לצאת מ-SnapBar ולפתוח אותה מחדש.",
    "Import": "ייבוא",
    "Import Screenshots from the Desktop…": "ייבוא צילומים משולחן העבודה…",
    "Imported": "מיובאים",
    "It is on the clipboard. Click Copy to copy it again.": "הצילום כבר בלוח. לחיצה על העתק מעתיקה אותו שוב.",
    "It stays in the corner until you close it or use it. Drag it straight into a chat.":
        "היא נשארת בפינה עד שסוגרים אותה או משתמשים בה. אפשר לגרור ממנה ישר לצ'אט.",
    "Largest Files First": "הקבצים הגדולים קודם",
    "Last 30 Days": "30 הימים האחרונים",
    "Last 7 Days": "7 הימים האחרונים",
    "Later": "אחר כך",
    "Library": "ספרייה",
    "Library index": "אינדקס הספרייה",
    "Line": "קו",
    "Log": "יומן",
    "Maintenance": "תחזוקה",
    "Medium": "בינוני",
    "Minimize": "מזער",
    "Move old screenshots to the Trash": "העברת צילומים ישנים לפח",
    "Move the screenshots already on your Desktop into the SnapBar folder so they show up in the library.":
        "אפשר להעביר את הצילומים שכבר נמצאים בשולחן העבודה לתיקיית SnapBar, כדי שיופיעו בספרייה.",
    "Move this screenshot to the Trash?": "להעביר את הצילום הזה לפח?",
    "Move to Trash": "העבר לפח",
    "Never": "אף פעם",
    "Newest First": "החדשים קודם",
    "No screenshots to import": "אין צילומים לייבוא",
    "No screenshots yet": "עוד אין צילומים",
    "Not allowed": "לא מאושר",
    "Not allowed yet": "עוד לא מאושר",
    "Not asked yet": "עוד לא נשאל",
    "Nothing matches these filters": "אין צילומים שמתאימים לסינון",
    "Notifications": "התראות",
    "Notifications (optional)": "התראות (לא חובה)",
    "Oldest First": "הישנים קודם",
    "One folder for everything. You can change it any time in Settings.":
        "תיקייה אחת לכל הצילומים. אפשר לשנות אותה בכל רגע בהגדרות.",
    "Open Log File": "פתח את קובץ היומן",
    "Open Screenshots Folder": "פתח את תיקיית הצילומים",
    "Open SnapBar when you log in": "לפתוח את SnapBar כשהמחשב עולה",
    "Open System Settings": "פתח את הגדרות המערכת",
    "Open the library": "פתיחת הספרייה",
    "Panel": "חלונית",
    "Paste": "הדבק",
    "Pen": "עט",
    "Play the shutter sound": "להשמיע צליל צמצם",
    "Press keys…": "הקש מקשים…",
    "Press ⇧⌘S to take your first one. It will appear here.": "לוחצים ⇧⌘S לצילום הראשון, והוא יופיע כאן.",
    "Quit SnapBar": "צא מ-SnapBar",
    "Rebuild Thumbnails": "בנה מחדש את התמונות הממוזערות",
    "Record Shortcut": "הקלט קיצור",
    "Rectangle": "מלבן",
    "Redo": "בצע שוב",
    "Regular macOS screenshots": "צילומי מסך רגילים של macOS",
    "Regular macOS screenshots (⇧⌘4)": "צילומי מסך רגילים של macOS (⇧⌘4)",
    "Remove from Favorites": "הסר מהמועדפים",
    "Replace": "החלף",
    "Replace the original screenshot?": "להחליף את הצילום המקורי?",
    "Request Access": "בקש הרשאה",
    "Reset Crop": "בטל חיתוך",
    "Restore Default Shortcuts": "שחזר את קיצורי ברירת המחדל",
    "Save": "שמור",
    "Save As PNG…": "שמור בשם כ-PNG…",
    "Save As…": "שמור בשם…",
    "Save Retina screenshots at 1x size": "לשמור צילומי Retina בגודל 1x",
    "Save them in the SnapBar folder": "לשמור אותם בתיקיית SnapBar",
    "Save them in the SnapBar folder instead of the Desktop": "לשמור אותם בתיקיית SnapBar במקום בשולחן העבודה",
    "Saving": "שמירה",
    "Screenshot Library": "ספריית צילומים",
    "Screenshot Library…": "ספריית צילומים…",
    "Screenshot saved": "הצילום נשמר",
    "Screenshots folder": "תיקיית הצילומים",
    "Screenshots in the library": "צילומים בספרייה",
    "Screenshots on the Desktop": "צילומים בשולחן העבודה",
    "Screenshots that paste right away and never get lost.": "צילומי מסך שמודבקים מיד ולא הולכים לאיבוד.",
    "Search text in screenshots": "חיפוש טקסט בתוך הצילומים",
    "Select All": "בחר הכל",
    "Settings…": "הגדרות…",
    "Shortcuts": "קיצורים",
    "Show a panel in the corner after each screenshot": "להציג חלונית בפינה אחרי כל צילום",
    "Show in Finder": "הצג ב-Finder",
    "Show the Welcome Guide Again": "הצג שוב את מדריך הפתיחה",
    "SnapBar": "SnapBar",
    "SnapBar needs Screen Recording permission. Open System Settings, turn on SnapBar under Screen Recording, then capture again.":
        "SnapBar צריכה הרשאת הקלטת מסך. פותחים את הגדרות המערכת, מדליקים את SnapBar תחת הקלטת מסך, ומצלמים שוב.",
    "SnapBar uses a notification only if you turn the corner panel off.": "SnapBar שולחת התראה רק כשהחלונית בפינה כבויה.",
    "Sort": "מיון",
    "Source": "מקור",
    "Start Using SnapBar": "מתחילים לעבוד",
    "Startup": "הפעלה",
    "Step Number": "מספור שלבים",
    "Text": "טקסט",
    "The marks become part of the picture. Use Save As to keep the original.":
        "הסימונים יהפכו לחלק מהתמונה. כדי לשמור את המקור, משתמשים בשמור בשם.",
    "The panel stays until you close it or use it. Up to five stack in the corner.":
        "החלונית נשארת עד שסוגרים אותה או משתמשים בה. עד חמש חלוניות נערמות בפינה.",
    "The screenshot came out empty": "הצילום יצא ריק",
    "The second switch changes a macOS setting. It stays off unless you turn it on.":
        "המתג השני משנה הגדרה של macOS. הוא כבוי עד שמדליקים אותו.",
    "There are no screenshots on your Desktop to import.": "אין בשולחן העבודה צילומים לייבוא.",
    "They move from %@ into %@ and show up in the library.": "הם יעברו מ-%1$@ אל %2$@ ויופיעו בספרייה.",
    "Thick": "עבה",
    "Thin": "דק",
    "This Month": "החודש",
    "This changes where macOS itself saves ⇧⌘4 screenshots. Turn it off to go back to the Desktop.":
        "זה משנה לאן macOS עצמה שומרת צילומי ⇧⌘4. כיבוי מחזיר את השמירה לשולחן העבודה.",
    "Thumbnail Size": "גודל התמונות",
    "Tidy up your Desktop": "מסדרים את שולחן העבודה",
    "To": "עד תאריך",
    "Today": "היום",
    "Tools": "כלים",
    "Top left": "למעלה משמאל",
    "Top right": "למעלה מימין",
    "Try another date or clear the search.": "אפשר לנסות תאריך אחר או לנקות את החיפוש.",
    "Type here": "כתבו כאן",
    "Undo": "בטל פעולה",
    "Version": "גרסה",
    "View": "תצוגה",
    "Welcome to SnapBar": "ברוכים הבאים ל-SnapBar",
    "When the panel is off": "כשהחלונית כבויה",
    "Where screenshots are saved": "איפה הצילומים נשמרים",
    "Window": "חלון",
    "Yesterday": "אתמול",
    "You can restore them from the Trash.": "אפשר לשחזר אותם מהפח.",
    "Your marks will be lost. Copy or save first to keep them.": "הסימונים יאבדו. כדי לשמור אותם, קודם מעתיקים או שומרים.",
    "Zoom In": "הגדל",
    "Zoom Out": "הקטן",
    "Zoom to Fit": "התאם לחלון",
    "edited": "ערוך",
    "macOS Screenshots": "צילומי macOS",
    "macOS already uses %@.": "macOS כבר משתמשת ב-%@.",
    "macOS asks every app that takes screenshots for this permission. Without it, screenshots come out empty.":
        "macOS מבקשת את ההרשאה הזו מכל אפליקציה שמצלמת מסך. בלעדיה הצילומים יוצאים ריקים.",
    "⇧⌘4 keeps working. SnapBar can catch those screenshots too.": "⇧⌘4 ממשיך לעבוד. SnapBar יכולה לתפוס גם את הצילומים האלה.",
    "⇧⌘S copies and saves": "⇧⌘S מעתיק ושומר",
    "menu.edit": "עריכה",
    "menu.file": "קובץ",
    "menu.view": "תצוגה",
    "menu.tools": "כלים",
    "menu.window": "חלון",
    "editor.subtitle": "עריכה",
}

# Keys whose English source differs from the key itself.
EN_SOURCE = {
    "menu.edit": "Edit", "menu.file": "File", "menu.view": "View",
    "menu.tools": "Tools", "menu.window": "Window", "editor.subtitle": "Editing",
}

# Counted strings: Hebrew CLDR plural forms one / two / other.
PLURAL = {
    "%lld screenshots": ("צילום מסך אחד", "שני צילומי מסך", "%lld צילומי מסך"),
    "%lld screenshots found on the Desktop.": ("נמצא צילום מסך אחד בשולחן העבודה.", "נמצאו שני צילומי מסך בשולחן העבודה.", "נמצאו %lld צילומי מסך בשולחן העבודה."),
    "Copy %lld Screenshots": ("העתק צילום אחד", "העתק שני צילומים", "העתק %lld צילומים"),
    "Import %lld Screenshots…": ("ייבוא צילום אחד…", "ייבוא שני צילומים…", "ייבוא %lld צילומים…"),
    "Import %lld screenshots?": ("לייבא צילום אחד?", "לייבא שני צילומים?", "לייבא %lld צילומים?"),
    "Move %lld screenshots to the Trash?": ("להעביר צילום אחד לפח?", "להעביר שני צילומים לפח?", "להעביר %lld צילומים לפח?"),
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    derived = os.path.expanduser("~/Library/Developer/SnapBar/DerivedData/Build/Intermediates.noindex/SnapBar.build")
    extracted = set()
    for f in glob.glob(derived + "/**/*.stringsdata", recursive=True):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except ValueError:
            continue
        for entry in data.get("tables", {}).get("Localizable", []):
            if entry.get("key") is not None:
                extracted.add(entry["key"])

    strings = {}
    for key, he in HE.items():
        item = {"localizations": {"he": unit(he)}}
        if key in EN_SOURCE:
            item["localizations"]["en"] = unit(EN_SOURCE[key])
        strings[key] = item
    for key, (one, two, other) in PLURAL.items():
        strings[key] = {"localizations": {"he": {"variations": {"plural": {
            "one": unit(one), "two": unit(two), "other": unit(other)}}}}}

    missing = sorted(k for k in extracted if k not in strings)
    unused = sorted(k for k in strings if extracted and k not in extracted)
    catalog = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
    out = os.path.join(root, "SnapBar", "Resources", "Localizable.xcstrings")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(catalog, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print("keys in catalog:", len(strings), "| extracted from build:", len(extracted))
    if unused:
        print("not used by the current build:", unused)
    if missing:
        print("MISSING HEBREW for:", missing)
        sys.exit(1)
    print("every extracted key has Hebrew")


if __name__ == "__main__":
    main()
