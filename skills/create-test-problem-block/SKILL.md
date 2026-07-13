---
name: create-test-problem-block
description: Full 3-step problem block test workflow. Step 1 builds a 92-unit Open edX course in Studio (14 subsections, all problem types, OLX populated, published, user enrolled). Step 2 clones it as a "-Wrong Submissions" re-run course for wrong-answer testing. Step 3 runs Playwright headed Chrome to submit correct answers on the original (verify all show Correct), spot-check the re-run, then submit wrong answers on the re-run (verify all show Incorrect). Use when asked to "set up problem block testing", "create problem block test course", "build the problem block test structure", or "run problem block browser tests".
argument-hint: [studio-url] [lms-url] [username] [password]
allowed-tools: Bash(curl:*), Bash(python3:*), Bash(grep:*), Bash(cat:*), Bash(find:*), Bash(ls:*), Bash(rm:*)
---

# Create Test Problem Block Skill

Builds a fully-structured Problem Block test course in a local Open edX Studio instance, with all 92 test cases populated with meaningful OLX content.

The test matrix targets the three capa JS files: `display.js` (all standard response types, hints, feedback, partial credit, Show Answer, reset, submit-wait timer, equation previews), `imageinput.js` (Image Mapped Input), and `schematic.js` (Circuit Schematic Builder).

---

## Overview

| Step | What it does | When to run |
|---|---|---|
| **Step 1: Course Creation** | Builds the 92-unit course in Studio, uploads assets, publishes, enrols user. | First run, or when you need a fresh course. |
| **Step 2: Re-Run Course** | Creates `{title} -Wrong Submissions` (run `2026_WS`) with identical content. | After Step 1, keeps the original clean for Step 3.1. |
| **Step 3: Browser Testing** | Playwright headed Chrome — correct submissions on original (3.1), spot-check re-run (3.2), wrong submissions on re-run (3.3). | After Steps 1 & 2. |

**Automatable problems (80/92):** Single Select, Multi-Select, Dropdown, Numerical Input, Text Input, Custom Python, Math Expression, Adaptive Hint, Multipart, Choice Text Input.

**Skipped (12 — manual testing needed):** Image Mapped Input ×4, Circuit Schematic Builder ×3, Custom JavaScript ×3, Chemical Equation Input ×2.

Each Step is independent — re-run Step 3 without repeating Steps 1 & 2. The temp files used are:
- Step 1: `/tmp/seq_map.json`, `/tmp/verticals.json`, `/tmp/problem_progress.json`
- Step 2: `/tmp/seq_map_ws.json`, `/tmp/verticals_ws.json`, `/tmp/problem_progress_ws.json`

---

## Step 1: Course Creation

---

## Phase 1: Gather Credentials

Start by asking this question:

> "What is the name of the Course you want to create?"

Store the answer as `COURSE_TITLE`.

Use these defaults for all other connection details — do **not** ask for them upfront:

| Variable | Default |
|---|---|
| `STUDIO_URL` | `http://studio.local.openedx.io:8001` |
| `LMS_URL` | `http://local.openedx.io:8000` |
| `USERNAME` | `edx@example.com` |
| `PASSWORD` | `edx` |

If authentication fails (non-200 response from the login API), ask explicitly:

> "Authentication failed. Please provide your Studio URL, LMS URL, username, and password."

If the Studio URL is unreachable (connection error or non-2xx on the first Studio request), ask explicitly:

> "Could not reach the Studio at `http://studio.local.openedx.io:8001`. Please share the correct Studio URL."

---

## Phase 2: Authenticate

### 2a. Clear any stale cookies, then get a fresh CSRF token from LMS

```bash
rm -f /tmp/openedx_cookies.txt
curl -s -c /tmp/openedx_cookies.txt "$LMS_URL/login" > /dev/null
LMS_CSRF=$(grep csrftoken /tmp/openedx_cookies.txt | awk '{print $NF}' | tail -1)
echo "LMS CSRF: $LMS_CSRF"
```

### 2b. Login via LMS session API

Use `--data-urlencode` to avoid encoding issues with special characters in the password:

```bash
LOGIN_RESULT=$(curl -s \
  -c /tmp/openedx_cookies.txt \
  -b /tmp/openedx_cookies.txt \
  -X POST "$LMS_URL/api/user/v1/account/login_session/" \
  -H "X-CSRFToken: $LMS_CSRF" \
  -H "Referer: $LMS_URL/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "email=$USERNAME" \
  --data-urlencode "password=$PASSWORD")
echo "Login: $LOGIN_RESULT"
```

Verify `"success": true` in the response. If not, stop and report the error.

### 2c. Warm up Studio session and extract Studio CSRF

```bash
curl -s -L \
  -c /tmp/openedx_cookies.txt \
  -b /tmp/openedx_cookies.txt \
  "$STUDIO_URL/home" > /dev/null

# Extract the Studio-specific csrftoken (domain: studio.local.openedx.io)
STUDIO_CSRF=$(grep "studio.local.openedx.io" /tmp/openedx_cookies.txt | grep csrftoken | awk '{print $NF}')
echo "Studio CSRF: $STUDIO_CSRF"
```

> **Important**: The LMS and Studio use **different** cookie domains (`local.openedx.io` vs `studio.local.openedx.io`), so the cookies file contains two separate `csrftoken` entries. Always grep for the Studio-specific one. The `-L` flag is required to follow Studio's SSO redirect chain, which is what causes the Studio cookie to be set. If Studio CSRF calls return 403 later, re-run this step to refresh the token.

---

## Phase 3: Create the Course

```bash
COURSE_RESP=$(curl -s \
  -b /tmp/openedx_cookies.txt \
  -X POST "$STUDIO_URL/api/v1/course_runs/" \
  -H "X-CSRFToken: $STUDIO_CSRF" \
  -H "Referer: $STUDIO_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"org\": \"Axim\",
    \"number\": \"ProblemBlockJS\",
    \"run\": \"2026_T1\",
    \"title\": \"$COURSE_TITLE\"
  }")
echo "Course: $COURSE_RESP"
```

Extract and store:

```bash
COURSE_ID=$(echo "$COURSE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
echo "COURSE_ID: $COURSE_ID"
```

If the course already exists (HTTP 400), ask the user for the existing `COURSE_ID`.

Derive the course-level block locator immediately (used in Phases 4 and 8):

```bash
# e.g. course-v1:Axim+ProblemBlockJS+2026_T1 → block-v1:Axim+ProblemBlockJS+2026_T1+type@course+block@course
COURSE_BLOCK_ID="block-v1:${COURSE_ID#course-v1:}+type@course+block@course"
echo "COURSE_BLOCK_ID: $COURSE_BLOCK_ID"
```

---

## Phase 3.5: Upload Static Assets

The Image Mapped Input and Custom JavaScript units reference static files. These ship with this skill in the `assets/` directory **next to this SKILL.md** — resolve `SKILL_ASSETS` from the location this skill was loaded from:

| File | Used by |
|---|---|
| `paris_map.png` | Image Mapped: single rectangle (target at (230,80)-(280,250)) |
| `floor_plan.png` | Image Mapped: two rectangles (doors at (50,180)-(120,220) and (480,180)-(550,220)) |
| `region_map.png` | Image Mapped: polygon triangle + quadrant unit (midlines at x=300, y=200) |
| `jsinput_dropdown.html` | Custom JS: dynamic dropdown (`JSInputDropdown`) |
| `jsinput_colorpicker.html` | Custom JS: color picker (`ColorPicker`) |
| `jsinput_slider.html` | Custom JS: slider (`Slider`) |

Upload each via the Studio assets API:

```bash
SKILL_ASSETS="<directory containing this SKILL.md>/assets"

for f in paris_map.png floor_plan.png region_map.png \
         jsinput_dropdown.html jsinput_colorpicker.html jsinput_slider.html; do
  curl -s -b /tmp/openedx_cookies.txt \
    -X POST "$STUDIO_URL/assets/$COURSE_ID/" \
    -H "X-CSRFToken: $STUDIO_CSRF" \
    -H "Referer: $STUDIO_URL" \
    -H "Accept: application/json" \
    -F "file=@$SKILL_ASSETS/$f" \
    -o /dev/null -w "$f → HTTP_%{http_code}\n"
done
```

All six must return HTTP_200. If any return 403, refresh the Studio CSRF token (Phase 2c) and retry the failed files. Once uploaded, the `/static/<filename>` references in the Phase 7 OLX resolve automatically at render time.

> The image target regions were drawn to match the OLX coordinates exactly, so click-grading works out of the box. The jsinput HTML files implement the JSInput contract (`getGrade`/`getState`/`setState` returning JSON state) that the Phase 7 `cfn` graders parse.

---

## Phase 4: Create the Section

```bash
CHAPTER_RESP=$(curl -s \
  -b /tmp/openedx_cookies.txt \
  -X POST "$STUDIO_URL/xblock/" \
  -H "X-CSRFToken: $STUDIO_CSRF" \
  -H "Referer: $STUDIO_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"parent_locator\": \"$COURSE_BLOCK_ID\",
    \"category\": \"chapter\",
    \"display_name\": \"Problem Block Testing\"
  }")

CHAPTER_ID=$(echo "$CHAPTER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('locator',''))")
echo "CHAPTER_ID: $CHAPTER_ID"
```

Stop if `CHAPTER_ID` is empty.

---

## Phase 5: Create the 14 Subsections

Use a Python script to create all 14 sequentials and save their locators. Save to `/tmp/seq_map.json` so later phases can reference them.

```python
import json, subprocess

STUDIO_URL = "http://studio.local.openedx.io:8001"
COOKIES = "/tmp/openedx_cookies.txt"
CHAPTER_ID = "<from Phase 4>"

def get_csrf():
    content = open(COOKIES).read()
    lines = [l for l in content.split('\n') if 'csrftoken' in l and 'studio' in l and l.strip()]
    if not lines:
        lines = [l for l in content.split('\n') if 'csrftoken' in l and l.strip()]
    return lines[-1].split()[-1] if lines else ''

def refresh_csrf():
    subprocess.run(['curl', '-s', '-L', '-c', COOKIES, '-b', COOKIES,
                    f'{STUDIO_URL}/home', '-o', '/dev/null'], check=False)
    return get_csrf()

subsections = [
    "Single Select", "Multi-Select", "Dropdown", "Numerical Input",
    "Text Input", "Custom Python-Evaluated Input",
    "Custom JavaScript Display and Grading", "Image Mapped Input",
    "Math Expression Input", "Problem with Adaptive Hint",
    "Multipart Components", "Circuit Schematic Builder",
    "Chemical Equation Input", "Choice Text Input",
]

csrf = get_csrf()
seq_map = {}

for name in subsections:
    payload = json.dumps({
        "parent_locator": CHAPTER_ID,
        "category": "sequential",
        "display_name": name
    })
    for attempt in range(3):
        r = subprocess.run([
            'curl', '-s', '-b', COOKIES,
            '-X', 'POST', f'{STUDIO_URL}/xblock/',
            '-H', f'X-CSRFToken: {csrf}',
            '-H', 'Referer: ' + STUDIO_URL,
            '-H', 'Content-Type: application/json',
            '-d', payload,
            '-w', '\nHTTP_CODE:%{http_code}'
        ], capture_output=True, text=True)
        body, _, code = r.stdout.rpartition('\nHTTP_CODE:')
        if code.strip() == '403':
            csrf = refresh_csrf()
            continue
        data = json.loads(body)
        locator = data.get('locator', '')
        if locator:
            seq_map[name] = locator
            print(f"  OK: {name} → {locator[:50]}")
        else:
            print(f"  ERROR: no locator for {name}")
        break

with open('/tmp/seq_map.json', 'w') as f:
    json.dump(seq_map, f, indent=2)

print(f"\n{len(seq_map)}/14 subsections created")
assert len(seq_map) == 14, "Expected 14 subsections — stop and investigate before continuing"
```

---

## Phase 6: Create Units (Verticals) per Subsection

Use a Python script to create all 92 verticals and save to `/tmp/verticals.json`.

```python
import json, subprocess

STUDIO_URL = "http://studio.local.openedx.io:8001"
COOKIES = "/tmp/openedx_cookies.txt"

seq_map = json.load(open('/tmp/seq_map.json'))

def get_csrf():
    content = open(COOKIES).read()
    lines = [l for l in content.split('\n') if 'csrftoken' in l and 'studio' in l and l.strip()]
    if not lines:
        lines = [l for l in content.split('\n') if 'csrftoken' in l and l.strip()]
    return lines[-1].split()[-1] if lines else ''

def refresh_csrf():
    subprocess.run(['curl', '-s', '-L', '-c', COOKIES, '-b', COOKIES,
                    f'{STUDIO_URL}/home', '-o', '/dev/null'], check=False)
    return get_csrf()

UNITS = {
    "Single Select": [
        "Standard configuration with basic answers",
        "Explanation fields with answer visibility settings",
        "Advanced attempt restrictions",
        "Answer-specific feedback using speech bubble icons",
        "Hints system with multiple hint levels",
        "Basic partial credit (0.25 points for specific answers)",
        "Shuffle answers feature for randomization",
        "Targeted feedback with explanation IDs",
        "Demand hints (on-click reveal)",
        "Answer pools with random subset selection",
        "Simple Markdown syntax with parentheses",
        "Markdown with explanation blocks",
        "Show Answer button reveals the correct choice",
        "Submission wait timer between attempts",
    ],
    "Multi-Select": [
        "Standard checkbox selections (vegetables)",
        "Custom weight and timed attempts settings",
        "Per-option feedback configuration",
        "Hints UI with geography examples",
        "Attempt limits and reset options",
        "Partial credit using EDC (Every Decision Counts) mode",
        "Partial credit using halves method",
        "Compound hints based on answer combinations",
        "Advanced choice hints for selected vs. unselected states",
        "Python scripting with randomization",
        "Simple Markdown checkbox syntax",
        "Markdown with explanation blocks",
    ],
    "Dropdown": [
        "Basic geography questions",
        "Math questions with explanations",
        "Attempt limits (one-shot scenarios)",
        "Animal classification examples",
        "Yes/No boolean logic",
        "Standard tuple configuration using options attribute",
        "Inline dropdowns within sentences (cloze style)",
        "Individual option hints and feedback",
        "Labeled option hints with custom headers",
        "Full problems with solution blocks and demand hints",
        "Simple dropdown Markdown with double brackets",
        "Dropdown with explanation blocks",
    ],
    "Numerical Input": [
        "Simple math operations",
        "Decimal precision with tolerance ranges",
        "Percentage tolerance settings",
        "Large number handling",
        "Negative number inputs",
        "Basic percentage tolerance (2% margin)",
        "Scientific notation with alternative answers",
        "Partial credit with close range scoring",
        "Python scripted calculations (Pythagorean theorem)",
        "Trailing text for units display",
        "Simple Markdown numerical format",
        "Markdown with percentage tolerance and explanations",
        "Rerandomize on reset with scripted variables",
    ],
    "Text Input": [
        "Basic vocabulary synonym checking",
        "Multiple acceptable answers configuration",
        "Input width adjustment for long responses",
        "Case-insensitive matching (USA variants)",
        "Case-sensitive password checking",
        "Regular expression pattern matching",
        "Specific feedback for common misconceptions",
        "Trailing text and input size visualization",
        "Simple Markdown text input with alternatives",
        "Markdown with regex and explanations",
        "Multi-field text input with combined feedback",
        "Text input with randomized answer variants",
    ],
    "Custom Python-Evaluated Input": [
        "Math constraint validation (sum to expected value)",
        "Partial credit scoring based on input percentage",
        "Randomized parameters with dynamic math",
        "Multi-input specific feedback per field",
        "String logic including palindrome checking",
    ],
    "Custom JavaScript Display and Grading": [
        "Dynamic dropdown with JSON state management",
        "Visual color picker (click interaction)",
        "Slider math with numerical logic",
    ],
    "Image Mapped Input": [
        "Single rectangular region definition",
        "Multiple rectangular regions (either correct)",
        "Irregular polygon regions using coordinate points",
        "Multiple image inputs in one problem",
    ],
    "Math Expression Input": [
        "Basic algebra (kinetic energy formula)",
        "Greek variables and trigonometric functions",
        "Python-scripted variable generation (parallel resistors)",
        "Inline LaTeX rendering in the prompt (MathJax)",
    ],
    "Problem with Adaptive Hint": [
        "Math logic riddle with trap answers",
        "Geography with common misconception hints",
        "Chemistry symbols with close-match detection",
    ],
    "Multipart Components": [
        "Mixed input types (checkbox + numerical)",
        "Language exam (dropdown + text + multiple choice)",
        "Reading comprehension with contextual grouping",
    ],
    "Circuit Schematic Builder": [
        "Default circuit schematic with voltage divider example",
        "Transient analysis signal mixer requiring specific component ratios",
        "Preloaded circuit via initial_value",
    ],
    "Chemical Equation Input": [
        "Balanced chemical equation with live preview",
        "Ionic charges with superscript preview rendering",
    ],
    "Choice Text Input": [
        "Radio buttons with embedded numeric input (radiotextgroup)",
        "Checkboxes with embedded numeric inputs (checkboxtextgroup)",
    ],
}

csrf = get_csrf()
verticals = []

for seq_name, unit_list in UNITS.items():
    seq_id = seq_map.get(seq_name)
    if not seq_id:
        print(f"ERROR: No seq_id for {seq_name}")
        continue
    for unit_name in unit_list:
        payload = json.dumps({
            "parent_locator": seq_id,
            "category": "vertical",
            "display_name": unit_name
        })
        for attempt in range(3):
            r = subprocess.run([
                'curl', '-s', '-b', COOKIES,
                '-X', 'POST', f'{STUDIO_URL}/xblock/',
                '-H', f'X-CSRFToken: {csrf}',
                '-H', 'Referer: ' + STUDIO_URL,
                '-H', 'Content-Type: application/json',
                '-d', payload,
                '-w', '\nHTTP_CODE:%{http_code}'
            ], capture_output=True, text=True)
            body, _, code = r.stdout.rpartition('\nHTTP_CODE:')
            if code.strip() == '403':
                csrf = refresh_csrf()
                continue
            data = json.loads(body)
            locator = data.get('locator', '')
            if locator:
                verticals.append({'seq': seq_name, 'name': unit_name, 'id': locator})
                print(f"  OK: {seq_name} / {unit_name}")
            else:
                print(f"  ERROR: no locator for {seq_name} / {unit_name}")
            break

with open('/tmp/verticals.json', 'w') as f:
    json.dump(verticals, f, indent=2)

print(f"\n{len(verticals)}/92 verticals created")
assert len(verticals) == 92, "Expected 92 verticals — stop and investigate before continuing"
```

---

## Phase 7: Create Problem Blocks with OLX

> **Critical rules — read before running:**
> - This script saves progress to `/tmp/problem_progress.json` after each successful block.
> - If interrupted, re-run the **same script unchanged** — it will skip already-done blocks automatically.
> - **Never re-create `/tmp/verticals.json`** between a partial Phase 7 run and a retry — that would generate new vertical IDs and create duplicates.
> - On 403 errors the script refreshes the CSRF token and retries automatically.
> - If the `locator` field is missing from a creation response, the script logs the failure and continues — it does **not** create a second attempt at that block.

Write the full script to `/tmp/create_problems.py`, then run it:

```python
#!/usr/bin/env python3
"""Phase 7: Idempotent problem-block creation with OLX.
   Resume-safe: skips verticals already in /tmp/problem_progress.json.
"""
import json, subprocess, os

STUDIO_URL = "http://studio.local.openedx.io:8001"
COOKIES = "/tmp/openedx_cookies.txt"
PROGRESS_FILE = "/tmp/problem_progress.json"

# ── Helpers ───────────────────────────────────────────────────────────────────

def get_csrf():
    try:
        content = open(COOKIES).read()
        lines = [l for l in content.split('\n') if 'csrftoken' in l and 'studio' in l and l.strip()]
        if not lines:
            lines = [l for l in content.split('\n') if 'csrftoken' in l and l.strip()]
        return lines[-1].split()[-1] if lines else ''
    except:
        return ''

def refresh_csrf():
    subprocess.run(['curl', '-s', '-L', '-c', COOKIES, '-b', COOKIES,
                    f'{STUDIO_URL}/home', '-o', '/dev/null'], check=False)
    return get_csrf()

def post_json(path, payload_dict, csrf):
    payload = json.dumps(payload_dict)
    r = subprocess.run([
        'curl', '-s', '-b', COOKIES,
        '-X', 'POST', f'{STUDIO_URL}{path}',
        '-H', f'X-CSRFToken: {csrf}',
        '-H', 'Referer: ' + STUDIO_URL,
        '-H', 'Content-Type: application/json',
        '-d', payload,
        '-w', '\nHTTP_CODE:%{http_code}'
    ], capture_output=True, text=True)
    body, _, code = r.stdout.rpartition('\nHTTP_CODE:')
    return body.strip(), code.strip()

# ── OLX dictionary (keyed by unit name; duplicates keyed by "Seq::Name") ──────

OLX = {

# ─── Single Select ───────────────────────────────────────────────────────────

"Standard configuration with basic answers": """<problem>
  <multiplechoiceresponse>
    <label>What is the capital of France?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">Berlin</choice>
      <choice correct="true">Paris</choice>
      <choice correct="false">Madrid</choice>
      <choice correct="false">Rome</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Explanation fields with answer visibility settings": """<problem showanswer="finished">
  <multiplechoiceresponse>
    <label>Which planet is closest to the Sun?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">Venus</choice>
      <choice correct="true">Mercury</choice>
      <choice correct="false">Earth</choice>
      <choice correct="false">Mars</choice>
    </choicegroup>
  </multiplechoiceresponse>
  <solution>
    <div class="detailed-solution">
      <p>Mercury orbits the Sun at an average distance of 57.9 million km.</p>
    </div>
  </solution>
</problem>""",

"Advanced attempt restrictions": """<problem max_attempts="2" showanswer="after_attempts">
  <multiplechoiceresponse>
    <label>What is 7 × 8?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">54</choice>
      <choice correct="false">64</choice>
      <choice correct="true">56</choice>
      <choice correct="false">48</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Answer-specific feedback using speech bubble icons": """<problem>
  <multiplechoiceresponse>
    <label>Which of the following is a mammal?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">Salmon<choicehint>Salmon is a fish, not a mammal.</choicehint></choice>
      <choice correct="true">Dolphin<choicehint>Correct! Dolphins are marine mammals.</choicehint></choice>
      <choice correct="false">Eagle<choicehint>Eagles are birds, not mammals.</choicehint></choice>
      <choice correct="false">Cobra<choicehint>Cobras are reptiles, not mammals.</choicehint></choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Hints system with multiple hint levels": """<problem>
  <multiplechoiceresponse>
    <label>What is the chemical symbol for gold?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">Gd</choice>
      <choice correct="false">Go</choice>
      <choice correct="true">Au</choice>
      <choice correct="false">Ag</choice>
    </choicegroup>
  </multiplechoiceresponse>
  <demandhint>
    <hint>The symbol comes from the Latin name for gold.</hint>
    <hint>The Latin word for gold is "aurum".</hint>
    <hint>The symbol is the first two letters of "aurum".</hint>
  </demandhint>
</problem>""",

"Basic partial credit (0.25 points for specific answers)": """<problem>
  <multiplechoiceresponse partial_credit="points">
    <label>Which of the following is closest to a primary color (RYB)?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="true" point_value="1">Red</choice>
      <choice correct="false" point_value="0.25">Orange</choice>
      <choice correct="false" point_value="0">Green</choice>
      <choice correct="false" point_value="0">Purple</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Shuffle answers feature for randomization": """<problem>
  <multiplechoiceresponse>
    <label>What is the largest ocean on Earth?</label>
    <choicegroup type="MultipleChoice" shuffle="true">
      <choice correct="false">Atlantic Ocean</choice>
      <choice correct="true">Pacific Ocean</choice>
      <choice correct="false">Indian Ocean</choice>
      <choice correct="false">Arctic Ocean</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Targeted feedback with explanation IDs": """<problem targeted-feedback="">
  <multiplechoiceresponse targeted-feedback="alwaysShowCorrectChoiceExplanation">
    <label>Which gas makes up most of Earth's atmosphere?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false" explanation-id="oxygen">Oxygen</choice>
      <choice correct="true" explanation-id="nitrogen">Nitrogen</choice>
      <choice correct="false" explanation-id="co2">Carbon Dioxide</choice>
      <choice correct="false" explanation-id="argon">Argon</choice>
    </choicegroup>
    <targetedfeedbackset>
      <targetedfeedback explanation-id="oxygen">Oxygen makes up about 21% of the atmosphere.</targetedfeedback>
      <targetedfeedback explanation-id="nitrogen">Correct! Nitrogen is ~78% of Earth's atmosphere.</targetedfeedback>
      <targetedfeedback explanation-id="co2">CO₂ is only ~0.04% of the atmosphere.</targetedfeedback>
      <targetedfeedback explanation-id="argon">Argon makes up ~0.93% of the atmosphere.</targetedfeedback>
    </targetedfeedbackset>
  </multiplechoiceresponse>
</problem>""",

"Demand hints (on-click reveal)": """<problem>
  <multiplechoiceresponse>
    <label>Who wrote "Romeo and Juliet"?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">Charles Dickens</choice>
      <choice correct="false">Jane Austen</choice>
      <choice correct="true">William Shakespeare</choice>
      <choice correct="false">Mark Twain</choice>
    </choicegroup>
  </multiplechoiceresponse>
  <demandhint>
    <hint>This author was born in Stratford-upon-Avon in 1564.</hint>
    <hint>He is often called the "Bard of Avon".</hint>
  </demandhint>
</problem>""",

"Answer pools with random subset selection": """<problem>
  <multiplechoiceresponse>
    <label>Which of the following is a programming language?</label>
    <choicegroup type="MultipleChoice" answer-pool="4">
      <choice correct="true">Python</choice>
      <choice correct="false">HTML</choice>
      <choice correct="false">CSS</choice>
      <choice correct="false">JSON</choice>
      <choice correct="false">XML</choice>
      <choice correct="false">Markdown</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Simple Markdown syntax with parentheses": """<problem>
  <multiplechoiceresponse>
    <label>What is the boiling point of water at sea level?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">90°C</choice>
      <choice correct="true">100°C</choice>
      <choice correct="false">110°C</choice>
      <choice correct="false">80°C</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Single Select::Markdown with explanation blocks": """<problem>
  <multiplechoiceresponse>
    <label>What does HTTP stand for?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">HyperText Transfer Package</choice>
      <choice correct="true">HyperText Transfer Protocol</choice>
      <choice correct="false">High Transfer Text Protocol</choice>
      <choice correct="false">HyperText Transport Process</choice>
    </choicegroup>
  </multiplechoiceresponse>
  <solution>
    <div class="detailed-solution">
      <p>HTTP stands for HyperText Transfer Protocol — the foundation of data communication on the Web.</p>
    </div>
  </solution>
</problem>""",

"Show Answer button reveals the correct choice": """<problem showanswer="always" max_attempts="5">
  <multiplechoiceresponse>
    <label>Which element has the atomic number 1?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="true">Hydrogen</choice>
      <choice correct="false">Helium</choice>
      <choice correct="false">Oxygen</choice>
      <choice correct="false">Carbon</choice>
    </choicegroup>
  </multiplechoiceresponse>
  <solution>
    <div class="detailed-solution">
      <p>Hydrogen has a single proton, giving it atomic number 1. Click "Show Answer" to reveal the correct choice highlighting.</p>
    </div>
  </solution>
</problem>""",

"Submission wait timer between attempts": """<problem submission_wait_seconds="30" max_attempts="5">
  <multiplechoiceresponse>
    <label>How many continents are there on Earth? (After submitting, the Submit button is disabled for 30 seconds — verify the countdown message appears.)</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">5</choice>
      <choice correct="false">6</choice>
      <choice correct="true">7</choice>
      <choice correct="false">8</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

# ─── Multi-Select ─────────────────────────────────────────────────────────────

"Standard checkbox selections (vegetables)": """<problem>
  <choiceresponse>
    <label>Which of the following are vegetables? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Carrot</choice>
      <choice correct="true">Broccoli</choice>
      <choice correct="false">Apple</choice>
      <choice correct="false">Banana</choice>
      <choice correct="true">Spinach</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Custom weight and timed attempts settings": """<problem weight="2" max_attempts="3">
  <choiceresponse>
    <label>Which of the following are continents? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Africa</choice>
      <choice correct="true">Europe</choice>
      <choice correct="false">Atlantic</choice>
      <choice correct="true">Asia</choice>
      <choice correct="false">Caribbean</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Per-option feedback configuration": """<problem>
  <choiceresponse>
    <label>Which of the following are mammals? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Whale
        <choicehint selected="true">Correct! Whales are marine mammals.</choicehint>
        <choicehint selected="false">Whales breathe air and nurse young — they are mammals.</choicehint>
      </choice>
      <choice correct="true">Bat
        <choicehint selected="true">Correct! Bats are the only flying mammals.</choicehint>
        <choicehint selected="false">Bats are mammals, not birds.</choicehint>
      </choice>
      <choice correct="false">Crocodile
        <choicehint selected="true">Crocodiles are reptiles, not mammals.</choicehint>
        <choicehint selected="false">Correct — crocodiles are reptiles.</choicehint>
      </choice>
      <choice correct="false">Tuna
        <choicehint selected="true">Tuna are fish, not mammals.</choicehint>
        <choicehint selected="false">Correct — tuna are fish.</choicehint>
      </choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Hints UI with geography examples": """<problem>
  <choiceresponse>
    <label>Which countries are in South America? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Brazil</choice>
      <choice correct="true">Argentina</choice>
      <choice correct="false">Mexico</choice>
      <choice correct="true">Chile</choice>
      <choice correct="false">Spain</choice>
    </checkboxgroup>
  </choiceresponse>
  <demandhint>
    <hint>South America is the continent south of Central America.</hint>
    <hint>Mexico is in North America; Spain is in Europe.</hint>
  </demandhint>
</problem>""",

"Attempt limits and reset options": """<problem max_attempts="2" show_reset_button="true">
  <choiceresponse>
    <label>Which of the following are prime numbers? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="false">1</choice>
      <choice correct="true">2</choice>
      <choice correct="true">3</choice>
      <choice correct="false">4</choice>
      <choice correct="true">5</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Partial credit using EDC (Every Decision Counts) mode": """<problem>
  <choiceresponse partial_credit="EDC">
    <label>Which of the following are programming languages? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Python</choice>
      <choice correct="true">Java</choice>
      <choice correct="false">HTML</choice>
      <choice correct="true">C++</choice>
      <choice correct="false">CSS</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Partial credit using halves method": """<problem>
  <choiceresponse partial_credit="halves">
    <label>Which of the following are planets in our solar system? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Mars</choice>
      <choice correct="true">Jupiter</choice>
      <choice correct="false">Pluto</choice>
      <choice correct="true">Neptune</choice>
      <choice correct="false">Ceres</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Compound hints based on answer combinations": """<problem>
  <choiceresponse>
    <label>Which of the following are renewable energy sources? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Solar</choice>
      <choice correct="true">Wind</choice>
      <choice correct="false">Coal</choice>
      <choice correct="false">Natural Gas</choice>
      <choice correct="true">Hydropower</choice>
    </checkboxgroup>
    <compoundhint value="A B">Solar and wind are correct, but you missed hydropower.</compoundhint>
    <compoundhint value="C D">Coal and natural gas are fossil fuels — not renewable.</compoundhint>
  </choiceresponse>
</problem>""",

"Advanced choice hints for selected vs. unselected states": """<problem>
  <choiceresponse>
    <label>Which of the following are bodies of water? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Ocean
        <choicehint selected="true">Yes, oceans are large saltwater bodies.</choicehint>
        <choicehint selected="false">The ocean is a body of water — consider selecting it.</choicehint>
      </choice>
      <choice correct="true">Lake
        <choicehint selected="true">Correct! Lakes are enclosed freshwater bodies.</choicehint>
        <choicehint selected="false">Lakes are bodies of water surrounded by land.</choicehint>
      </choice>
      <choice correct="false">Mountain
        <choicehint selected="true">Mountains are landforms, not bodies of water.</choicehint>
        <choicehint selected="false">Correct — mountains are not bodies of water.</choicehint>
      </choice>
      <choice correct="false">Desert
        <choicehint selected="true">Deserts are dry landforms, not bodies of water.</choicehint>
        <choicehint selected="false">Correct — deserts are not bodies of water.</choicehint>
      </choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Python scripting with randomization": """<problem>
  <choiceresponse>
    <label>Which of the following are primary colors in the RYB model? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Red</choice>
      <choice correct="true">Blue</choice>
      <choice correct="true">Yellow</choice>
      <choice correct="false">Green</choice>
      <choice correct="false">Purple</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Simple Markdown checkbox syntax": """<problem>
  <choiceresponse>
    <label>Which of the following are types of databases? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">Relational</choice>
      <choice correct="true">NoSQL</choice>
      <choice correct="false">Procedural</choice>
      <choice correct="true">Graph</choice>
      <choice correct="false">Sequential</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

"Multi-Select::Markdown with explanation blocks": """<problem>
  <choiceresponse>
    <label>Which of the following are Python data types? (Select all that apply)</label>
    <checkboxgroup>
      <choice correct="true">list</choice>
      <choice correct="true">dict</choice>
      <choice correct="false">array</choice>
      <choice correct="true">tuple</choice>
      <choice correct="false">vector</choice>
    </checkboxgroup>
  </choiceresponse>
  <solution>
    <div class="detailed-solution">
      <p>Python built-in types include list, dict, tuple, set, str, int, float, and bool.</p>
    </div>
  </solution>
</problem>""",

# ─── Dropdown ────────────────────────────────────────────────────────────────

"Basic geography questions": """<problem>
  <optionresponse>
    <label>What is the capital of Japan?</label>
    <optioninput options="('Beijing','Tokyo','Seoul','Bangkok')" correct="Tokyo"/>
  </optionresponse>
</problem>""",

"Math questions with explanations": """<problem showanswer="finished">
  <optionresponse>
    <label>What is the square root of 144?</label>
    <optioninput options="('10','11','12','13')" correct="12"/>
  </optionresponse>
  <solution><div class="detailed-solution"><p>12 × 12 = 144, so √144 = 12.</p></div></solution>
</problem>""",

"Attempt limits (one-shot scenarios)": """<problem max_attempts="1">
  <optionresponse>
    <label>Which country has the largest population?</label>
    <optioninput options="('USA','India','China','Brazil')" correct="India"/>
  </optionresponse>
</problem>""",

"Animal classification examples": """<problem>
  <optionresponse>
    <label>A shark is classified as which type of animal?</label>
    <optioninput options="('Mammal','Bird','Fish','Reptile')" correct="Fish"/>
  </optionresponse>
</problem>""",

"Yes/No boolean logic": """<problem>
  <optionresponse>
    <label>Is the Earth older than the Moon?</label>
    <optioninput options="('Yes','No')" correct="No"/>
  </optionresponse>
  <solution><div class="detailed-solution"><p>The Moon formed ~4.5 billion years ago, shortly after Earth (4.54 billion years ago).</p></div></solution>
</problem>""",

"Standard tuple configuration using options attribute": """<problem>
  <optionresponse>
    <label>What is the SI unit of electric current?</label>
    <optioninput options="('Volt','Ohm','Ampere','Watt')" correct="Ampere"/>
  </optionresponse>
</problem>""",

"Inline dropdowns within sentences (cloze style)": """<problem>
  <p>The speed of light in a vacuum is approximately
  <optionresponse inline="1">
    <optioninput options="('300,000','150,000','500,000')" correct="300,000" inline="1"/>
  </optionresponse>
  km/s, and light travels from the Sun to Earth in about
  <optionresponse inline="1">
    <optioninput options="('4','8','12','16')" correct="8" inline="1"/>
  </optionresponse>
  minutes.</p>
</problem>""",

"Individual option hints and feedback": """<problem>
  <optionresponse>
    <label>Which layer of Earth is liquid?</label>
    <optioninput options="('Crust','Mantle','Outer Core','Inner Core')" correct="Outer Core"/>
  </optionresponse>
  <demandhint>
    <hint>Earth has four layers: crust, mantle, outer core, and inner core.</hint>
    <hint>The inner core is solid due to extreme pressure.</hint>
  </demandhint>
</problem>""",

"Labeled option hints with custom headers": """<problem>
  <optionresponse>
    <label>What is the powerhouse of the cell?</label>
    <optioninput options="('Nucleus','Ribosome','Mitochondria','Golgi Apparatus')" correct="Mitochondria"/>
  </optionresponse>
  <demandhint>
    <hint>This organelle produces ATP through cellular respiration.</hint>
    <hint>It has its own DNA and a double membrane.</hint>
  </demandhint>
</problem>""",

"Full problems with solution blocks and demand hints": """<problem showanswer="finished">
  <optionresponse>
    <label>Which programming paradigm does Python primarily support?</label>
    <optioninput options="('Purely Functional','Purely Object-Oriented','Multi-paradigm','Procedural only')" correct="Multi-paradigm"/>
  </optionresponse>
  <solution><div class="detailed-solution"><p>Python supports OOP, procedural, and functional paradigms.</p></div></solution>
  <demandhint>
    <hint>Python supports classes and objects.</hint>
    <hint>Python also supports lambda, map(), and filter().</hint>
  </demandhint>
</problem>""",

"Simple dropdown Markdown with double brackets": """<problem>
  <optionresponse>
    <label>What is the default port for HTTPS?</label>
    <optioninput options="('80','443','8080','3000')" correct="443"/>
  </optionresponse>
</problem>""",

"Dropdown with explanation blocks": """<problem showanswer="always">
  <optionresponse>
    <label>Which data structure uses LIFO order?</label>
    <optioninput options="('Queue','Stack','Heap','Tree')" correct="Stack"/>
  </optionresponse>
  <solution><div class="detailed-solution"><p>A Stack uses LIFO — the last element added is the first removed.</p></div></solution>
</problem>""",

# ─── Numerical Input ─────────────────────────────────────────────────────────

"Simple math operations": """<problem>
  <numericalresponse answer="42">
    <label>What is 6 × 7?</label>
    <responseparam type="tolerance" default="0"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Decimal precision with tolerance ranges": """<problem>
  <numericalresponse answer="3.14159">
    <label>What is π to 5 decimal places?</label>
    <responseparam type="tolerance" default="0.001"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Percentage tolerance settings": """<problem>
  <numericalresponse answer="9.8">
    <label>What is the acceleration due to gravity on Earth (m/s²)?</label>
    <responseparam type="tolerance" default="5%"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Large number handling": """<problem>
  <numericalresponse answer="299792458">
    <label>What is the speed of light in a vacuum (m/s)?</label>
    <responseparam type="tolerance" default="1%"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Negative number inputs": """<problem>
  <numericalresponse answer="-273.15">
    <label>What is absolute zero in degrees Celsius?</label>
    <responseparam type="tolerance" default="0.5"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Basic percentage tolerance (2% margin)": """<problem>
  <numericalresponse answer="1000">
    <label>What is the area of a 40m × 25m rectangle in m²?</label>
    <responseparam type="tolerance" default="2%"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Scientific notation with alternative answers": """<problem>
  <numericalresponse answer="6.022e23">
    <label>What is Avogadro's number (mol⁻¹)?</label>
    <responseparam type="tolerance" default="1%"/>
    <additional_answer answer="6.02e23"/>
    <additional_answer answer="6.023e23"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Partial credit with close range scoring": """<problem>
  <numericalresponse answer="100" partial_credit="close">
    <label>What is the boiling point of water in °C?</label>
    <responseparam type="tolerance" default="0"/>
    <responseparam type="close_tolerance" default="10"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Python scripted calculations (Pythagorean theorem)": """<problem>
  <script type="loncapa/python">
import math
answer = math.sqrt(3**2 + 4**2)
  </script>
  <numericalresponse answer="$answer">
    <label>What is the length of the hypotenuse of a right triangle with legs 3 and 4?</label>
    <responseparam type="tolerance" default="0.01"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Trailing text for units display": """<problem>
  <numericalresponse answer="1000">
    <label>How many meters are in 1 kilometer?</label>
    <responseparam type="tolerance" default="0"/>
    <formulaequationinput trailing_text="meters"/>
  </numericalresponse>
</problem>""",

"Simple Markdown numerical format": """<problem>
  <numericalresponse answer="25">
    <label>What is 5 squared?</label>
    <responseparam type="tolerance" default="0"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Markdown with percentage tolerance and explanations": """<problem>
  <numericalresponse answer="1.989e30">
    <label>What is the approximate mass of the Sun in kilograms?</label>
    <responseparam type="tolerance" default="2%"/>
    <formulaequationinput/>
  </numericalresponse>
  <solution>
    <div class="detailed-solution">
      <p>The Sun has a mass of approximately 1.989 × 10³⁰ kg, about 333,000 times the mass of Earth.</p>
    </div>
  </solution>
</problem>""",

"Rerandomize on reset with scripted variables": """<problem rerandomize="onreset" show_reset_button="true">
  <script type="loncapa/python">
import random
a = random.randint(10, 50)
b = random.randint(10, 50)
answer = a + b
  </script>
  <numericalresponse answer="$answer">
    <label>What is $a + $b? (Submit, then click Reset — the numbers should change.)</label>
    <responseparam type="tolerance" default="0"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

# ─── Text Input ──────────────────────────────────────────────────────────────

"Basic vocabulary synonym checking": """<problem>
  <stringresponse answer="happy" type="ci">
    <label>Enter a synonym for "joyful":</label>
    <additional_answer answer="glad"/>
    <additional_answer answer="cheerful"/>
    <additional_answer answer="content"/>
    <textline size="20"/>
  </stringresponse>
</problem>""",

"Multiple acceptable answers configuration": """<problem>
  <stringresponse answer="H2O" type="ci">
    <label>What is the chemical formula for water?</label>
    <additional_answer answer="h2o"/>
    <additional_answer answer="water"/>
    <textline size="10"/>
  </stringresponse>
</problem>""",

"Input width adjustment for long responses": """<problem>
  <stringresponse answer="photosynthesis" type="ci">
    <label>What process do plants use to convert sunlight into food?</label>
    <textline size="40"/>
  </stringresponse>
</problem>""",

"Case-insensitive matching (USA variants)": """<problem>
  <stringresponse answer="USA" type="ci">
    <label>What is the abbreviation for the United States of America?</label>
    <additional_answer answer="US"/>
    <additional_answer answer="U.S.A."/>
    <additional_answer answer="U.S."/>
    <textline size="10"/>
  </stringresponse>
</problem>""",

"Case-sensitive password checking": """<problem>
  <stringresponse answer="OpenEdX2024" type="cs">
    <label>Enter the case-sensitive access code:</label>
    <textline size="20"/>
  </stringresponse>
</problem>""",

"Regular expression pattern matching": """<problem>
  <stringresponse answer="regexp:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}" type="regexp">
    <label>Enter a valid email address:</label>
    <textline size="30"/>
  </stringresponse>
</problem>""",

"Specific feedback for common misconceptions": """<problem>
  <stringresponse answer="mitochondria" type="ci">
    <label>What is the powerhouse of the cell?</label>
    <textline size="20"/>
    <hintgroup>
      <stringhint answer="nucleus" type="ci">
        <hintpart on="nucleus"><startouttext/>The nucleus controls the cell but does not produce energy.<endouttext/></hintpart>
      </stringhint>
      <stringhint answer="ribosome" type="ci">
        <hintpart on="ribosome"><startouttext/>Ribosomes synthesize proteins, not energy.<endouttext/></hintpart>
      </stringhint>
    </hintgroup>
  </stringresponse>
</problem>""",

"Trailing text and input size visualization": """<problem>
  <numericalresponse answer="60">
    <label>How many minutes are in one hour?</label>
    <responseparam type="tolerance" default="0"/>
    <formulaequationinput trailing_text="minutes"/>
  </numericalresponse>
</problem>""",

"Simple Markdown text input with alternatives": """<problem>
  <stringresponse answer="gravity" type="ci">
    <label>What force keeps planets in orbit around the Sun?</label>
    <additional_answer answer="gravitation"/>
    <additional_answer answer="gravitational force"/>
    <textline size="25"/>
  </stringresponse>
</problem>""",

"Markdown with regex and explanations": """<problem>
  <stringresponse answer="regexp:[0-9]{3}-[0-9]{3}-[0-9]{4}" type="regexp">
    <label>Enter a US phone number in the format 555-555-5555:</label>
    <textline size="15"/>
  </stringresponse>
  <solution>
    <div class="detailed-solution">
      <p>US phone numbers use the format: area code (3 digits), dash, 3 digits, dash, 4 digits.</p>
    </div>
  </solution>
</problem>""",

"Multi-field text input with combined feedback": """<problem>
  <stringresponse answer="George" type="ci">
    <label>First name of the author of "1984":</label>
    <textline size="15"/>
  </stringresponse>
  <stringresponse answer="Orwell" type="ci">
    <label>Last name of the author of "1984":</label>
    <textline size="15"/>
  </stringresponse>
</problem>""",

"Text input with randomized answer variants": """<problem>
  <script type="loncapa/python">
import random
pairs = [("France", "Paris"), ("Japan", "Tokyo"), ("Germany", "Berlin"), ("Brazil", "Brasilia")]
idx = random.randint(0, len(pairs)-1)
country = pairs[idx][0]
capital = pairs[idx][1]
  </script>
  <stringresponse answer="$capital" type="ci">
    <label>What is the capital of $country?</label>
    <textline size="20"/>
  </stringresponse>
</problem>""",

# ─── Custom Python-Evaluated Input ───────────────────────────────────────────

"Math constraint validation (sum to expected value)": """<problem>
  <customresponse cfn="check_sum" expect="100">
    <script type="loncapa/python">
def check_sum(expect, ans):
    try:
        return abs(float(ans) - float(expect)) &lt; 0.01
    except ValueError:
        return False
    </script>
    <label>Enter a number that equals 100:</label>
    <textline size="10" correct_answer="100"/>
  </customresponse>
</problem>""",

"Partial credit scoring based on input percentage": """<problem>
  <customresponse cfn="check_partial">
    <script type="loncapa/python">
def check_partial(expect, ans):
    try:
        val = float(ans)
        if val == 50:
            return True
        elif 40 &lt;= val &lt;= 60:
            return {"ok": "partial", "msg": "Close! The answer is 50."}
        return False
    except ValueError:
        return False
    </script>
    <label>What is half of 100?</label>
    <textline size="10" correct_answer="50"/>
  </customresponse>
</problem>""",

"Randomized parameters with dynamic math": """<problem>
  <script type="loncapa/python">
import random
a = random.randint(2, 9)
b = random.randint(2, 9)
answer = a * b
  </script>
  <customresponse cfn="check_product" expect="$answer">
    <script type="loncapa/python">
def check_product(expect, ans):
    try:
        return int(ans) == int(expect)
    except (ValueError, TypeError):
        return False
    </script>
    <label>What is $a × $b?</label>
    <textline size="10" correct_answer="$answer"/>
  </customresponse>
</problem>""",

"Multi-input specific feedback per field": """<problem>
  <customresponse cfn="check_coords">
    <script type="loncapa/python">
def check_coords(expect, ans):
    try:
        parts = str(ans).split(',')
        x, y = int(parts[0].strip()), int(parts[1].strip())
        if x == 3 and y == 4:
            return True
        elif x == 3:
            return {"ok": False, "msg": "x is correct, but y should be 4."}
        elif y == 4:
            return {"ok": False, "msg": "y is correct, but x should be 3."}
        return False
    except Exception:
        return False
    </script>
    <label>Enter coordinates (x,y) of the point 3 right and 4 up from the origin:</label>
    <textline size="10" correct_answer="3,4"/>
  </customresponse>
</problem>""",

"String logic including palindrome checking": """<problem>
  <customresponse cfn="check_palindrome">
    <script type="loncapa/python">
def check_palindrome(expect, ans):
    cleaned = str(ans).strip().lower()
    if len(cleaned) &gt; 0 and cleaned == cleaned[::-1]:
        return True
    return {"ok": False, "msg": "'" + str(ans) + "' is not a palindrome. Try: racecar, level, madam."}
    </script>
    <label>Enter any palindrome (a word that reads the same forwards and backwards):</label>
    <textline size="20" correct_answer="racecar"/>
  </customresponse>
</problem>""",

# ─── Custom JavaScript Display and Grading ───────────────────────────────────

"Dynamic dropdown with JSON state management": """<problem>
  <customresponse cfn="check_js_answer">
    <script type="loncapa/python">
def check_js_answer(expect, ans):
    import json
    try:
        state = json.loads(ans) if isinstance(ans, str) else ans
        return state.get("answer") == "correct"
    except Exception:
        return False
    </script>
    <p>This problem tests the JSInput block with a dynamic dropdown widget.</p>
    <jsinput
      html_file="/static/jsinput_dropdown.html"
      gradefn="JSInputDropdown.getGrade"
      get_statefn="JSInputDropdown.getState"
      set_statefn="JSInputDropdown.setState"
      width="400"
      height="120"
      initial_state='{"answer": ""}' />
  </customresponse>
</problem>""",

"Visual color picker (click interaction)": """<problem>
  <customresponse cfn="check_color">
    <script type="loncapa/python">
def check_color(expect, ans):
    import json
    try:
        state = json.loads(ans) if isinstance(ans, str) else ans
        return state.get("selected_color") == "blue"
    except Exception:
        return False
    </script>
    <p>This problem tests the JSInput block with a color picker widget. Click the blue color.</p>
    <jsinput
      html_file="/static/jsinput_colorpicker.html"
      gradefn="ColorPicker.getGrade"
      get_statefn="ColorPicker.getState"
      set_statefn="ColorPicker.setState"
      width="300"
      height="200"
      initial_state='{"selected_color": ""}' />
  </customresponse>
</problem>""",

"Slider math with numerical logic": """<problem>
  <customresponse cfn="check_slider">
    <script type="loncapa/python">
def check_slider(expect, ans):
    import json
    try:
        state = json.loads(ans) if isinstance(ans, str) else ans
        return abs(float(state.get("value", 0)) - 7.0) &lt; 0.5
    except Exception:
        return False
    </script>
    <p>This problem tests the JSInput block with a numeric slider. Set the slider to 7.</p>
    <jsinput
      html_file="/static/jsinput_slider.html"
      gradefn="Slider.getGrade"
      get_statefn="Slider.getState"
      set_statefn="Slider.setState"
      width="400"
      height="80"
      initial_state='{"value": 0}' />
  </customresponse>
</problem>""",

# ─── Image Mapped Input ───────────────────────────────────────────────────────

"Single rectangular region definition": """<problem>
  <imageresponse>
    <label>Click on the Eiffel Tower in the image below.</label>
    <imageinput src="/static/paris_map.png" width="600" height="400"
      rectangle="(230,80)-(280,250)"/>
  </imageresponse>
</problem>""",

"Multiple rectangular regions (either correct)": """<problem>
  <imageresponse>
    <label>Click on either exit door marked on the floor plan.</label>
    <imageinput src="/static/floor_plan.png" width="600" height="400"
      rectangle="(50,180)-(120,220),(480,180)-(550,220)"/>
  </imageresponse>
</problem>""",

"Irregular polygon regions using coordinate points": """<problem>
  <imageresponse>
    <label>Click anywhere inside the highlighted triangular region.</label>
    <imageinput src="/static/region_map.png" width="600" height="400"
      regions="[[[200,100],[350,100],[275,250]]]"/>
  </imageresponse>
</problem>""",

"Multiple image inputs in one problem": """<problem>
  <imageresponse>
    <label>Click anywhere in the top-left quadrant of the first image.</label>
    <imageinput src="/static/region_map.png" width="600" height="400"
      rectangle="(0,0)-(300,200)"/>
  </imageresponse>
  <imageresponse>
    <label>Click anywhere in the bottom-right quadrant of the second image.</label>
    <imageinput src="/static/region_map.png" width="600" height="400"
      rectangle="(300,200)-(600,400)"/>
  </imageresponse>
</problem>""",

# ─── Math Expression Input ────────────────────────────────────────────────────

"Basic algebra (kinetic energy formula)": """<problem>
  <formularesponse type="cs" samples="m,v@1,1:10,10#10" answer="0.5*m*v^2">
    <label>Write the formula for kinetic energy (KE) in terms of mass m and velocity v:</label>
    <responseparam type="tolerance" default="0.00001"/>
    <formulaequationinput/>
  </formularesponse>
</problem>""",

"Greek variables and trigonometric functions": """<problem>
  <formularesponse type="cs" samples="theta@0.1:3.0#10" answer="sin(theta)^2+cos(theta)^2">
    <label>Enter the Pythagorean trigonometric identity in terms of theta (should equal 1):</label>
    <responseparam type="tolerance" default="0.00001"/>
    <formulaequationinput/>
  </formularesponse>
</problem>""",

"Python-scripted variable generation (parallel resistors)": """<problem>
  <script type="loncapa/python">
import random
R1 = random.choice([100, 200, 500, 1000])
R2 = random.choice([100, 200, 500, 1000])
  </script>
  <formularesponse type="cs" samples="R1,R2@100,100:1000,1000#10" answer="(R1*R2)/(R1+R2)">
    <label>Write the formula for equivalent resistance of two parallel resistors R1 and R2:</label>
    <responseparam type="tolerance" default="1%"/>
    <formulaequationinput/>
  </formularesponse>
</problem>""",

"Inline LaTeX rendering in the prompt (MathJax)": """<problem>
  <formularesponse type="cs" samples="x@1:10#10" answer="x^2">
    <label>Enter the derivative of \\(f(x) = \\frac{x^3}{3}\\) with respect to x. (Verify the formula in the prompt renders via MathJax and the input shows a live preview as you type.)</label>
    <responseparam type="tolerance" default="0.00001"/>
    <formulaequationinput/>
  </formularesponse>
</problem>""",

# ─── Problem with Adaptive Hint ───────────────────────────────────────────────

"Math logic riddle with trap answers": """<problem>
  <stringresponse answer="9" type="ci">
    <label>I am a two-digit number. My tens digit is 0. My units digit is 9. What number am I?</label>
    <textline size="10"/>
    <hintgroup>
      <stringhint answer="90" type="ci">
        <hintpart on="90"><startouttext/>90 has a tens digit of 9, not 0. Re-read carefully.<endouttext/></hintpart>
      </stringhint>
    </hintgroup>
  </stringresponse>
</problem>""",

"Geography with common misconception hints": """<problem>
  <stringresponse answer="Canberra" type="ci">
    <label>What is the capital city of Australia?</label>
    <textline size="20"/>
    <hintgroup>
      <stringhint answer="Sydney" type="ci">
        <hintpart on="Sydney"><startouttext/>Sydney is the largest city, but not the capital.<endouttext/></hintpart>
      </stringhint>
      <stringhint answer="Melbourne" type="ci">
        <hintpart on="Melbourne"><startouttext/>Melbourne is a major city, but not the capital.<endouttext/></hintpart>
      </stringhint>
    </hintgroup>
  </stringresponse>
</problem>""",

"Chemistry symbols with close-match detection": """<problem>
  <stringresponse answer="Fe" type="cs">
    <label>What is the chemical symbol for iron?</label>
    <textline size="10"/>
    <hintgroup>
      <stringhint answer="fe" type="cs">
        <hintpart on="fe"><startouttext/>Chemical symbols are case-sensitive. First letter is uppercase.<endouttext/></hintpart>
      </stringhint>
      <stringhint answer="Ir" type="cs">
        <hintpart on="Ir"><startouttext/>Ir is Iridium. Iron's symbol comes from its Latin name "Ferrum".<endouttext/></hintpart>
      </stringhint>
    </hintgroup>
  </stringresponse>
</problem>""",

# ─── Multipart Components ────────────────────────────────────────────────────

"Mixed input types (checkbox + numerical)": """<problem>
  <choiceresponse>
    <label>Part A: Which are even numbers? (Select all)</label>
    <checkboxgroup>
      <choice correct="true">2</choice><choice correct="false">3</choice>
      <choice correct="true">4</choice><choice correct="false">7</choice>
      <choice correct="true">10</choice>
    </checkboxgroup>
  </choiceresponse>
  <numericalresponse answer="3">
    <label>Part B: How many odd numbers are in the list (2,3,4,7,10)?</label>
    <responseparam type="tolerance" default="0"/>
    <formulaequationinput/>
  </numericalresponse>
</problem>""",

"Language exam (dropdown + text + multiple choice)": """<problem>
  <optionresponse>
    <label>Part A: "___ apple a day keeps the doctor away."</label>
    <optioninput options="('a','an','the')" correct="an"/>
  </optionresponse>
  <stringresponse answer="plural" type="ci">
    <label>Part B: What grammatical form is "apples"?</label>
    <textline size="20"/>
  </stringresponse>
  <multiplechoiceresponse>
    <label>Part C: Which sentence is grammatically correct?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">She go to school every day.</choice>
      <choice correct="true">She goes to school every day.</choice>
      <choice correct="false">She going to school every day.</choice>
    </choicegroup>
  </multiplechoiceresponse>
</problem>""",

"Reading comprehension with contextual grouping": """<problem>
  <p><b>Passage:</b> <i>The water cycle describes the continuous movement of water within Earth and its atmosphere. It involves evaporation, condensation, precipitation, and collection.</i></p>
  <multiplechoiceresponse>
    <label>Q1: What does the water cycle describe?</label>
    <choicegroup type="MultipleChoice">
      <choice correct="false">The flow of rivers to the ocean</choice>
      <choice correct="true">The continuous movement of water within Earth and its atmosphere</choice>
      <choice correct="false">The formation of clouds</choice>
    </choicegroup>
  </multiplechoiceresponse>
  <choiceresponse>
    <label>Q2: Which stages are mentioned? (Select all)</label>
    <checkboxgroup>
      <choice correct="true">Evaporation</choice>
      <choice correct="true">Condensation</choice>
      <choice correct="false">Erosion</choice>
      <choice correct="true">Precipitation</choice>
    </checkboxgroup>
  </choiceresponse>
</problem>""",

# ─── Circuit Schematic Builder ────────────────────────────────────────────────

"Default circuit schematic with voltage divider example": """<problem>
  <p>Build a voltage divider with two 1kΩ resistors and a 10V source.</p>
  <schematicresponse>
    <center>
      <schematic height="500" width="600" parts="resistor voltage"
        analyses="dc" submit_button="Check Circuit"/>
    </center>
    <answer type="loncapa/python">
correct = [['dc', [['v', 10]]]]
ANSWER = answer[0][0] == 'dc'
    </answer>
  </schematicresponse>
</problem>""",

"Transient analysis signal mixer requiring specific component ratios": """<problem>
  <p>Build an RC network with a 1kΩ resistor, 1μF capacitor, and 5V source.</p>
  <schematicresponse>
    <center>
      <schematic height="500" width="600" parts="resistor capacitor voltage"
        analyses="tran" submit_button="Check Circuit"/>
    </center>
    <answer type="loncapa/python">
ANSWER = answer[0][0] == 'tran'
    </answer>
  </schematicresponse>
</problem>""",

"Preloaded circuit via initial_value": """<problem>
  <p>The schematic below should load with a 1kΩ resistor already placed on the canvas (verify the initial_value state restores). Add a 10V source to complete the circuit.</p>
  <schematicresponse>
    <center>
      <schematic height="500" width="600" parts="resistor voltage"
        analyses="dc" submit_button="Check Circuit"
        initial_value='[["r",[128,48,0],{"name":"R1","r":"1k"},["1","0"]]]'/>
    </center>
    <answer type="loncapa/python">
ANSWER = answer[0][0] == 'dc'
    </answer>
  </schematicresponse>
</problem>""",

# ─── Chemical Equation Input ──────────────────────────────────────────────────

"Balanced chemical equation with live preview": """<problem>
  <customresponse>
    <label>Enter the balanced equation for the combustion of hydrogen (type it and verify the formatted live preview appears below the input):</label>
    <chemicalequationinput size="50"/>
    <answer type="loncapa/python">
if chemcalc.chemical_equations_equal(submission[0], '2H2 + O2 -&gt; 2H2O'):
    correct = ['correct']
else:
    correct = ['incorrect']
    </answer>
  </customresponse>
</problem>""",

"Ionic charges with superscript preview rendering": """<problem>
  <customresponse>
    <label>Enter the equation for table salt dissociating in water (verify the ion charges render as superscripts in the live preview):</label>
    <chemicalequationinput size="50"/>
    <answer type="loncapa/python">
if chemcalc.chemical_equations_equal(submission[0], 'NaCl -&gt; Na^+ + Cl^-'):
    correct = ['correct']
else:
    correct = ['incorrect']
    </answer>
  </customresponse>
</problem>""",

# ─── Choice Text Input ────────────────────────────────────────────────────────

"Radio buttons with embedded numeric input (radiotextgroup)": """<problem>
  <choicetextresponse>
    <label>Solve 2x = 10. Select the correct statement and enter the value of x:</label>
    <radiotextgroup>
      <choice correct="true">The equation has a solution: x = <numtolerance_input answer="5"/></choice>
      <choice correct="false">The equation has no solution.</choice>
    </radiotextgroup>
  </choicetextresponse>
</problem>""",

"Checkboxes with embedded numeric inputs (checkboxtextgroup)": """<problem>
  <choicetextresponse>
    <label>Select every true statement and fill in the values:</label>
    <checkboxtextgroup>
      <choice correct="true">The square of 3 is <numtolerance_input answer="9"/></choice>
      <choice correct="true">The cube of 2 is <numtolerance_input answer="8"/></choice>
      <choice correct="false">Zero is a negative number.</choice>
    </checkboxtextgroup>
  </choicetextresponse>
</problem>""",

}  # end OLX dict

# ── Main loop ─────────────────────────────────────────────────────────────────

verticals = json.load(open('/tmp/verticals.json'))

# Load resume state
try:
    done_entries = json.load(open(PROGRESS_FILE))
    done_keys = {(e['seq'], e['name']) for e in done_entries}
    print(f"Resuming: {len(done_entries)} already done, {len(verticals)-len(done_entries)} remaining")
except FileNotFoundError:
    done_entries = []
    done_keys = set()

csrf = get_csrf()
if not csrf:
    csrf = refresh_csrf()

successes = len(done_entries)
failures = []

for vert in verticals:
    key = (vert['seq'], vert['name'])

    if key in done_keys:
        print(f"  SKIP: {vert['seq']} / {vert['name']}")
        continue

    # Look up OLX — try specific "Seq::Name" key first, then generic name
    olx = OLX.get(f"{vert['seq']}::{vert['name']}") or OLX.get(vert['name'])
    if not olx:
        print(f"  ERROR no OLX: {vert['seq']} / {vert['name']}")
        failures.append(key)
        continue

    # Step 1: Create problem block
    problem_id = None
    for attempt in range(3):
        body, code = post_json('/xblock/', {
            "parent_locator": vert['id'],
            "category": "problem",
            "display_name": vert['name']
        }, csrf)
        if code == '403':
            print(f"  403 on create — refreshing CSRF")
            csrf = refresh_csrf()
            continue
        if code != '200':
            print(f"  CREATE FAILED ({code}): {vert['seq']} / {vert['name']}")
            break
        try:
            data = json.loads(body)
            problem_id = data.get('locator', '')
            if not problem_id:
                print(f"  ERROR: empty locator in response: {body[:120]}")
        except Exception as e:
            print(f"  ERROR parsing response: {e} | body: {body[:120]}")
        break

    if not problem_id:
        failures.append(key)
        continue

    # Step 2: Write OLX payload to a temp file (avoids shell escaping of XML)
    olx_file = f'/tmp/_olx_{successes}.json'
    with open(olx_file, 'w') as f:
        json.dump({"data": olx, "publish": "make_public"}, f)

    # Step 3: POST OLX update
    update_ok = False
    for attempt in range(3):
        r2 = subprocess.run([
            'curl', '-s', '-b', COOKIES,
            '-X', 'POST', f'{STUDIO_URL}/xblock/{problem_id}',
            '-H', f'X-CSRFToken: {csrf}',
            '-H', 'Referer: ' + STUDIO_URL,
            '-H', 'Content-Type: application/json',
            '-d', f'@{olx_file}',
            '-w', '\nHTTP_CODE:%{http_code}'
        ], capture_output=True, text=True)
        _, _, olx_code = r2.stdout.rpartition('\nHTTP_CODE:')
        olx_code = olx_code.strip()
        if olx_code == '403':
            csrf = refresh_csrf()
            continue
        update_ok = (olx_code == '200')
        if not update_ok:
            print(f"  OLX update failed ({olx_code}): {vert['seq']} / {vert['name']}")
        break

    os.unlink(olx_file)

    if update_ok:
        entry = {
            'seq': vert['seq'],
            'name': vert['name'],
            'vertical_id': vert['id'],
            'problem_id': problem_id
        }
        done_entries.append(entry)
        done_keys.add(key)
        with open(PROGRESS_FILE, 'w') as f:
            json.dump(done_entries, f, indent=2)
        successes += 1
        print(f"  OK [{successes}/{len(verticals)}]: {vert['seq']} / {vert['name']}")
    else:
        failures.append(key)

print(f"\n=== Phase 7 complete: {successes} OK, {len(failures)} failed ===")
if failures:
    print("Failed units (re-run this script to retry):")
    for seq, name in failures:
        print(f"  {seq} / {name}")
```

Run with: `python3 /tmp/create_problems.py`

If any failures are printed, re-run the same script — it will skip done blocks and retry only the failed ones.

---

## Phase 7.5: Verify and Clean Empty Blocks Before Publishing

> **This phase is mandatory. Do not proceed to Phase 8 until this script exits with "✓ PASS".**

This single script verifies the course structure, automatically deletes any empty or duplicate problem blocks, republishes the draft to sync deletions, and re-checks until the structure is exactly right.

Write to `/tmp/verify_and_clean.py` and run it:

```python
#!/usr/bin/env python3
"""Phase 7.5: Verify structure. Auto-delete empty/duplicate blocks. Re-verify."""
import json, subprocess, urllib.parse, time

LMS_URL    = "http://local.openedx.io:8000"
STUDIO_URL = "http://studio.local.openedx.io:8001"
COOKIES    = "/tmp/openedx_cookies.txt"
COURSE_ID  = "<COURSE_ID from Phase 3>"   # e.g. course-v1:Axim+ProblemBlockJS+2026_T1

ENCODED_COURSE = urllib.parse.quote(COURSE_ID, safe='')
COURSE_BLOCK_ID = "block-v1:" + COURSE_ID.replace("course-v1:", "") + "+type@course+block@course"

# ── Helpers ───────────────────────────────────────────────────────────────────

def get_csrf():
    try:
        content = open(COOKIES).read()
        lines = [l for l in content.split('\n') if 'csrftoken' in l and 'studio' in l and l.strip()]
        if not lines:
            lines = [l for l in content.split('\n') if 'csrftoken' in l and l.strip()]
        return lines[-1].split()[-1] if lines else ''
    except:
        return ''

def refresh_csrf():
    subprocess.run(['curl', '-s', '-L', '-c', COOKIES, '-b', COOKIES,
                    f'{STUDIO_URL}/home', '-o', '/dev/null'], check=False)
    return get_csrf()

def fetch_blocks():
    r = subprocess.run([
        'curl', '-s', '-b', COOKIES,
        f'{LMS_URL}/api/courses/v1/blocks/?course_id={ENCODED_COURSE}'
        '&all_blocks=true&depth=all&username=edx&requested_fields=display_name,type,children',
        '-H', 'Accept: application/json'
    ], capture_output=True, text=True)
    return json.loads(r.stdout).get('blocks', {})

def delete_block(pid, csrf):
    for attempt in range(3):
        r = subprocess.run([
            'curl', '-s', '-b', COOKIES,
            '-X', 'DELETE', f'{STUDIO_URL}/xblock/{pid}',
            '-H', f'X-CSRFToken: {csrf}',
            '-H', 'Referer: ' + STUDIO_URL,
            '-w', '\nHTTP_CODE:%{http_code}'
        ], capture_output=True, text=True)
        _, _, code = r.stdout.rpartition('\nHTTP_CODE:')
        code = code.strip()
        if code == '403':
            csrf = refresh_csrf()
            continue
        return code in ('200', '204'), csrf
    return False, csrf

def republish(csrf):
    r = subprocess.run([
        'curl', '-s', '-b', COOKIES,
        '-X', 'POST', f'{STUDIO_URL}/xblock/{COURSE_BLOCK_ID}',
        '-H', f'X-CSRFToken: {csrf}',
        '-H', 'Referer: ' + STUDIO_URL,
        '-H', 'Content-Type: application/json',
        '-d', '{"publish": "make_public"}',
        '-w', '\nHTTP_CODE:%{http_code}'
    ], capture_output=True, text=True)
    _, _, code = r.stdout.rpartition('\nHTTP_CODE:')
    return code.strip()

# ── Load the intentional problem IDs from Phase 7 progress file ───────────────

try:
    good_ids = set(e['problem_id'] for e in json.load(open('/tmp/problem_progress.json')))
    print(f"Good IDs from progress file: {len(good_ids)}")
except FileNotFoundError:
    print("ERROR: /tmp/problem_progress.json not found — run Phase 7 first")
    raise SystemExit(1)

if len(good_ids) != 92:
    print(f"ERROR: progress file has {len(good_ids)} entries, expected 92 — re-run Phase 7")
    raise SystemExit(1)

# ── Main verify-and-clean loop (up to 3 passes) ───────────────────────────────

csrf = get_csrf()
MAX_PASSES = 3

for pass_num in range(1, MAX_PASSES + 1):
    print(f"\n─── Pass {pass_num} ───────────────────────────────────────────────")

    blocks = fetch_blocks()
    by_type = {}
    for b in blocks.values():
        by_type[b['type']] = by_type.get(b['type'], 0) + 1

    n_problems  = by_type.get('problem', 0)
    n_verticals = by_type.get('vertical', 0)
    n_seqs      = by_type.get('sequential', 0)

    print(f"  Problems: {n_problems}  |  Verticals: {n_verticals}  |  Sequentials: {n_seqs}")

    # ── Check for empty/orphan problem blocks (not in our progress file) ──────
    all_problem_ids = {bid for bid, b in blocks.items() if b['type'] == 'problem'}
    old_ids = all_problem_ids - good_ids

    # ── Check for verticals with 0 problem blocks ─────────────────────────────
    parent_map = {}
    for bid, b in blocks.items():
        for child in (b.get('children') or []):
            parent_map[child] = bid
    vert_children = {}
    for bid, b in blocks.items():
        if b['type'] == 'problem':
            p = parent_map.get(bid, '?')
            vert_children.setdefault(p, []).append(bid)
    empty_verticals = [bid for bid, b in blocks.items()
                       if b['type'] == 'vertical' and bid not in vert_children]

    # ── Decide action ─────────────────────────────────────────────────────────
    if n_problems == 92 and n_verticals == 92 and n_seqs == 14 and not old_ids:
        print("\n✓ PASS — Structure is correct: 92 problems in 92 units, 14 subsections.")
        print("  Safe to proceed to Phase 8.")
        raise SystemExit(0)

    if old_ids:
        print(f"\n  Found {len(old_ids)} old/empty block(s) — deleting...")
        deleted = 0
        for pid in old_ids:
            ok, csrf = delete_block(pid, csrf)
            if ok:
                deleted += 1
                print(f"    Deleted: {pid[:70]}")
            else:
                print(f"    Delete failed: {pid[:70]}")
        print(f"  Deleted {deleted}/{len(old_ids)}")

        print("  Republishing course to sync deletions...")
        pub_code = republish(csrf)
        print(f"  Publish response: {pub_code}")
        time.sleep(3)   # give LMS cache time to refresh
        continue        # re-check on next pass

    if n_problems < 92:
        missing = 92 - n_problems
        print(f"\n✗ FAIL — {missing} problem block(s) are missing.")
        print("  Re-run Phase 7 (the script is resume-safe and will fill the gaps).")
        raise SystemExit(1)

    if empty_verticals:
        print(f"\n✗ FAIL — {len(empty_verticals)} vertical(s) have no problem block.")
        print("  Re-run Phase 7 to fill the missing blocks.")
        raise SystemExit(1)

print(f"\n✗ FAIL — Could not reach a clean state after {MAX_PASSES} passes.")
print("  Investigate manually and re-run this script.")
raise SystemExit(1)
```

Run with: `python3 /tmp/verify_and_clean.py`

- If it prints `✓ PASS` → proceed to Phase 8.
- If it prints `✗ FAIL — missing blocks` → re-run Phase 7, then this script again.
- If it prints `✗ FAIL — could not reach clean state` → investigate manually.

---

## Phase 8: Publish the Course

```bash
# Refresh CSRF before publishing
curl -s -c /tmp/openedx_cookies.txt -b /tmp/openedx_cookies.txt \
  -L "$STUDIO_URL/home" > /dev/null
STUDIO_CSRF=$(grep csrftoken /tmp/openedx_cookies.txt | awk '{print $NF}' | tail -1)

# Publish entire course
curl -s -b /tmp/openedx_cookies.txt \
  -X POST "$STUDIO_URL/xblock/$COURSE_BLOCK_ID" \
  -H "X-CSRFToken: $STUDIO_CSRF" \
  -H "Referer: $STUDIO_URL" \
  -H "Content-Type: application/json" \
  -d '{"publish": "make_public"}' \
  -w "\nHTTP_%{http_code}"

# Set start date to today
curl -s -b /tmp/openedx_cookies.txt \
  -X POST "$STUDIO_URL/xblock/$COURSE_BLOCK_ID" \
  -H "X-CSRFToken: $STUDIO_CSRF" \
  -H "Referer: $STUDIO_URL" \
  -H "Content-Type: application/json" \
  -d "{\"metadata\": {\"start\": \"$(date -u +%Y-%m-%dT00:00:00Z)\"}}" \
  -w "\nHTTP_%{http_code}"
```

Both calls should return HTTP_200.

---

## Phase 9: Enrol the User

```bash
LMS_CSRF=$(grep csrftoken /tmp/openedx_cookies.txt | awk '{print $NF}' | tail -1)

curl -s -b /tmp/openedx_cookies.txt \
  -X POST "$LMS_URL/api/enrollment/v1/enrollment" \
  -H "X-CSRFToken: $LMS_CSRF" \
  -H "Referer: $LMS_URL" \
  -H "Content-Type: application/json" \
  -d "{\"course_details\": {\"course_id\": \"$COURSE_ID\"}}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('Enrolled:', d.get('is_active'), '| Mode:', d.get('mode'))"
```

Confirm `Enrolled: True`.

---

## Final Report

```
### create-test-problem-block complete

**Course:** $COURSE_ID
**Studio:** $STUDIO_URL/course/$COURSE_ID
**LMS:**    $LMS_URL/courses/$COURSE_ID/courseware
**Progress:** $LMS_URL/courses/$COURSE_ID/progress

**Structure built:**
- 1 section: "Problem Block Testing"
- 14 subsections (one per Problem Block type)
- 92 units with named test cases
- 92 Problem blocks with OLX content (verified)
- 6 static assets uploaded (3 region images, 3 jsinput widgets)
- Course published, start date: today
- User enrolled: $USERNAME

**JS coverage map (for capa JS regression testing):**
- `display.js` — Single Select, Multi-Select, Dropdown, Numerical, Text, Custom Python, Math Expression, Adaptive Hint, Multipart, Chemical Equation, Choice Text (submit/feedback/hints/partial credit/Show Answer/reset/wait timer/previews)
- `imageinput.js` — Image Mapped Input (4 units, incl. multiple instances per page)
- `schematic.js` — Circuit Schematic Builder (3 units, incl. initial_value restore)

**Suggested manual verification per subsection:** open the unit in the LMS, check DevTools console for new JS errors, submit a correct and an incorrect answer, confirm feedback/score updates, and exercise the unit's named feature (hint buttons, Show Answer, Reset, previews, timers).
```

---

## Notes

### Common pitfalls and how this skill avoids them

**Duplicate problem blocks**: Caused by running Phase 7 twice or a partial run followed by a full re-run. This skill avoids it by saving `/tmp/problem_progress.json` after each block and skipping already-done blocks on every run.

**CSRF token expiry during Phase 7**: The Studio CSRF token can expire during long-running loops. The Phase 7 script detects 403 responses, calls `refresh_csrf()`, and retries automatically without creating a duplicate block.

**Silent locator loss**: If the `locator` field is absent from the create-response, the script logs the failure and does **not** attempt to create a second block for that unit. The missing unit will appear in the failure list and be retried cleanly on the next run.

**OLX delivery**: The script writes each OLX payload to a temp file and uses `curl -d @file` rather than passing XML directly as a shell string. This prevents shell-escaping bugs with `<`, `>`, and quotes inside XML.

**Republish after cleanup**: If Phase 7.5 finds and deletes duplicate blocks, `POST /xblock/{COURSE_BLOCK_ID}` with `{"publish": "make_public"}` must be called again in Phase 8 to sync the LMS. Phase 8 always republishes for this reason.

**Progress files**: `/tmp/verticals.json`, `/tmp/seq_map.json`, and `/tmp/problem_progress.json` are created incrementally. Do not delete them between a partial Phase 7 run and a retry.

**LMS blocks API encoding**: The `+` signs in course IDs must be percent-encoded (`%2B`) when used as query parameters. Always use `urllib.parse.quote(COURSE_ID, safe='')`.

**OLX entities in Python scripts**: `<` and `>` inside Python code embedded in OLX must be written as `&lt;` and `&gt;` to keep the XML valid.

**Duplicate unit names**: "Markdown with explanation blocks" appears in both Single Select and Multi-Select. The OLX dict uses `"Single Select::Markdown with explanation blocks"` and `"Multi-Select::Markdown with explanation blocks"` as keys; the Phase 7 script checks the specific key first before falling back to the generic name.

**Codejail-dependent units**: Every unit whose OLX contains `<script type="loncapa/python">`, `<answer type="loncapa/python">`, or `chemcalc` needs codejail configured on the instance (Custom Python-Evaluated ×5, Circuit Schematic ×3, Chemical Equation ×2, plus the Python-scripted Numerical/Text/Math/Multi-Select variants). On instances without codejail these blocks render but fail on grading — report that as an environment limitation, not a content bug.

**Static asset dependencies**: The Image Mapped Input units reference `/static/paris_map.png`, `/static/floor_plan.png`, and `/static/region_map.png`, and the Custom JS units reference `/static/jsinput_*.html`. All six files ship in this skill's `assets/` directory and are uploaded in Phase 3.5 — if those units render broken images or empty iframes, Phase 3.5 was skipped or failed; re-run it (re-uploading is safe, Studio overwrites by filename).

---

## Step 2: Re-Run Course (-Wrong Submissions)

Uses **Studio's built-in re-run feature** to create an identical copy of the Step 1 course with a new run ID (`2026_WS`). This re-run course is used exclusively for wrong-submission testing (Step 3.3), keeping the original clean for correct-submission verification (Step 3.1).

### Prerequisites

- Step 1 course must be published (done in Phase 8)
- User must be authenticated (cookies in `/tmp/openedx_cookies.txt`)

### Execution

```bash
STUDIO_URL="http://studio.local.openedx.io:8001"
COOKIES="/tmp/openedx_cookies.txt"
COURSE_ID="course-v1:Axim+ProblemBlockJS+2026_T1"  # from Step 1 Phase 3
WS_COURSE_TITLE="${COURSE_TITLE} -Wrong Submissions"  # COURSE_TITLE from Step 1
WS_COURSE_RUN="2026_WS"

# Refresh Studio CSRF
curl -s -L -c "$COOKIES" -b "$COOKIES" "$STUDIO_URL/home" > /dev/null
STUDIO_CSRF=$(grep "studio.local.openedx.io" "$COOKIES" | grep csrftoken | awk '{print $NF}')

# Create re-run course via Studio API
RERUN_RESP=$(curl -s -b "$COOKIES" \
  -X POST "$STUDIO_URL/api/v1/course_runs/$COURSE_ID/rerun/" \
  -H "X-CSRFToken: $STUDIO_CSRF" \
  -H "Content-Type: application/json" \
  -d "{\"display_name\": \"$WS_COURSE_TITLE\", \"run\": \"$WS_COURSE_RUN\"}")

echo "Re-run response: $RERUN_RESP"

# Extract the new COURSE_ID from response
WS_COURSE_ID=$(echo "$RERUN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('course_key',''))")
echo "WS_COURSE_ID: $WS_COURSE_ID"
```

**Expected response:**
```json
{
  "course_key": "course-v1:Axim+ProblemBlockJS+2026_WS",
  "display_name": "Problem Block JS Testing -Wrong Submissions",
  "run": "2026_WS",
  ...
}
```

The re-run is **automatically published** — no Phase 8 needed.

### Enrol User

After the re-run is created, enrol the user (Phase 9):

```bash
LMS_URL="http://local.openedx.io:8000"
LMS_CSRF=$(grep "^local.openedx.io" "$COOKIES" | grep csrftoken | awk '{print $NF}')

curl -s -b "$COOKIES" \
  -X POST "$LMS_URL/api/enrollment/v1/enrollment" \
  -H "X-CSRFToken: $LMS_CSRF" \
  -H "Referer: $LMS_URL" \
  -H "Content-Type: application/json" \
  -d "{\"course_details\": {\"course_id\": \"$WS_COURSE_ID\"}}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('Enrolled:', d.get('is_active'), '| Mode:', d.get('mode'))"
```

**Expected:** `Enrolled: True | Mode: audit`

After completion, report both course links:

```
Step 2 complete:
  Original:   http://local.openedx.io:8000/courses/course-v1:Axim+ProblemBlockJS+2026_T1/courseware
  Re-run (WS): http://local.openedx.io:8000/courses/$WS_COURSE_ID/courseware
```

---

## Step 3: Browser Testing

Uses **Playwright** (headed Chromium — visible Chrome window) to submit answers to all 80 automatable problem blocks and verify each responds correctly.

**Automatable (80):** Single Select, Multi-Select, Dropdown, Numerical Input, Text Input, Custom Python, Math Expression, Adaptive Hint, Multipart, Choice Text Input.

**Skipped (12 — manual):** Image Mapped Input ×4, Circuit Schematic ×3, Custom JavaScript ×3, Chemical Equation ×2.

---

### Step 3.0: Install Playwright

```bash
pip install playwright 2>/dev/null || pip3 install playwright
playwright install chromium
mkdir -p /tmp/pb_screenshots
```

Verify: `python3 -c "from playwright.sync_api import sync_playwright; print('OK')"` — must print `OK`.

---

### Step 3.1: Correct Submissions (Original Course)

Goal: submit the correct answer to every automatable problem, confirm each shows "Correct", screenshot every result.

Write `/tmp/pb_correct_submit.py` and run it:

```python
#!/usr/bin/env python3
"""Step 3.1 — submit correct answers to all automatable problems on the original course."""
import json, subprocess, urllib.parse, os, time
import xml.etree.ElementTree as ET
from playwright.sync_api import sync_playwright

LMS_URL    = "http://local.openedx.io:8000"
STUDIO_URL = "http://studio.local.openedx.io:8001"
COOKIES    = "/tmp/openedx_cookies.txt"
COURSE_ID  = "<COURSE_ID from Step 1 Phase 3>"   # e.g. course-v1:Axim+ProblemBlockJS+2026_T1
SHOTS_DIR  = "/tmp/pb_screenshots/correct"
os.makedirs(SHOTS_DIR, exist_ok=True)

SKIP_TYPES = {'jsinput', 'imageresponse', 'schematicresponse', 'chemicalequationinput',
              'customresponse'}   # customresponse uses loncapa Python grading — skip canvas/widget types

# ── Helpers ───────────────────────────────────────────────────────────────────

def lms_blocks(course_id, block_type):
    encoded = urllib.parse.quote(course_id, safe='')
    r = subprocess.run([
        'curl', '-s', '-b', COOKIES,
        f'{LMS_URL}/api/courses/v1/blocks/?course_id={encoded}'
        f'&all_blocks=true&depth=all&block_types_filter={block_type}'
        '&return_type=list&page_size=500'
    ], capture_output=True, text=True)
    return json.loads(r.stdout)

def get_studio_csrf():
    content = open(COOKIES).read()
    lines = [l for l in content.split('\n') if 'csrftoken' in l and 'studio' in l and l.strip()]
    if not lines:
        lines = [l for l in content.split('\n') if 'csrftoken' in l and l.strip()]
    return lines[-1].split()[-1] if lines else ''

def get_olx(problem_id):
    r = subprocess.run([
        'curl', '-s', '-L', '-b', COOKIES,
        '-H', 'Accept: application/json',
        f'{STUDIO_URL}/xblock/{problem_id}'
    ], capture_output=True, text=True)
    try:
        return json.loads(r.stdout).get('data', '')
    except:
        return ''

def parse_answer(olx):
    """Parse OLX and return the correct answer action dict, or {'type':'skip'}."""
    if not olx:
        return {'type': 'skip', 'reason': 'empty OLX'}
    try:
        root = ET.fromstring(olx)
    except ET.ParseError:
        return {'type': 'skip', 'reason': 'XML parse error'}

    # Skip hard widget types
    for tag in SKIP_TYPES:
        if root.find(f'.//{tag}') is not None:
            return {'type': 'skip', 'reason': tag}

    actions = []

    # Multiple choice (radio)
    for resp in root.findall('.//multiplechoiceresponse'):
        choices = resp.findall('.//choice')
        for i, c in enumerate(choices):
            if c.get('correct') == 'true':
                actions.append({'type': 'radio', 'index': i})
                break

    # Checkbox
    for resp in root.findall('.//choiceresponse'):
        choices = resp.findall('.//choice')
        indices = [i for i, c in enumerate(choices) if c.get('correct') == 'true']
        if indices:
            actions.append({'type': 'checkbox', 'indices': indices})

    # Dropdown (optionresponse)
    for resp in root.findall('.//optionresponse'):
        for inp in resp.findall('.//optioninput'):
            correct = inp.get('correct', '')
            if correct:
                actions.append({'type': 'option', 'text': correct})
                break

    # Numerical
    for resp in root.findall('.//numericalresponse'):
        actions.append({'type': 'fill', 'selector': 'input.input-main, input.math, .numerical-input input', 'value': resp.get('answer', '0')})

    # String
    for resp in root.findall('.//stringresponse'):
        actions.append({'type': 'fill', 'selector': 'input.text-input, input[type="text"]', 'value': resp.get('answer', '')})

    # Formula
    for resp in root.findall('.//formularesponse'):
        actions.append({'type': 'fill', 'selector': 'input.math', 'value': resp.get('answer', '0')})

    # Choice text (radio + embedded number)
    for resp in root.findall('.//choicetextresponse'):
        radio_choices = resp.findall('.//radiotextgroup/choice')
        check_choices = resp.findall('.//checkboxtextgroup/choice')
        if radio_choices:
            for i, c in enumerate(radio_choices):
                if c.get('correct') == 'true':
                    num = c.find('.//numtolerance_input')
                    val = num.get('answer', '') if num is not None else ''
                    actions.append({'type': 'choicetext_radio', 'index': i, 'value': val})
                    break
        if check_choices:
            for i, c in enumerate(check_choices):
                if c.get('correct') == 'true':
                    num = c.find('.//numtolerance_input')
                    val = num.get('answer', '') if num is not None else ''
                    actions.append({'type': 'choicetext_check', 'index': i, 'value': val})

    if not actions:
        return {'type': 'skip', 'reason': 'no parseable response type'}
    return {'type': 'multi', 'actions': actions} if len(actions) > 1 else actions[0]

def apply_answer(page, answer):
    """Apply an answer action to the current problem page."""
    if answer['type'] == 'skip':
        return False

    actions = answer['actions'] if answer['type'] == 'multi' else [answer]

    for act in actions:
        t = act['type']
        if t == 'radio':
            page.locator('.choicegroup input[type="radio"]').nth(act['index']).click()
        elif t == 'checkbox':
            # Uncheck all first
            for cb in page.locator('.choicegroup input[type="checkbox"]').all():
                if cb.is_checked():
                    cb.uncheck()
            for idx in act['indices']:
                page.locator('.choicegroup input[type="checkbox"]').nth(idx).check()
        elif t == 'option':
            page.locator('select.input-large, .option-input select').first.select_option(label=act['text'])
        elif t == 'fill':
            inputs = page.locator(act['selector'])
            if inputs.count() > 0:
                inputs.first.fill(act['value'])
        elif t == 'choicetext_radio':
            page.locator('.choicetextgroup input[type="radio"]').nth(act['index']).click()
            num_inputs = page.locator('.choicetextgroup input[type="text"]')
            if num_inputs.count() > 0:
                num_inputs.first.fill(str(act['value']))
        elif t == 'choicetext_check':
            page.locator('.choicetextgroup input[type="checkbox"]').nth(act['index']).check()
            num_inputs = page.locator('.choicetextgroup input[type="text"]')
            if num_inputs.count() > 0:
                num_inputs.nth(act['index']).fill(str(act['value']))
    return True

# ── Main ──────────────────────────────────────────────────────────────────────

# Build {unit_name: vertical_id} and {unit_name: problem_id}
print("Fetching course structure from LMS...")
verticals = lms_blocks(COURSE_ID, 'vertical')
vert_map  = {v['display_name']: v['id'] for v in verticals}

problems  = lms_blocks(COURSE_ID, 'problem')
prob_map  = {p['display_name']: p['id'] for p in problems}

print(f"  {len(vert_map)} verticals, {len(prob_map)} problems")

results = []

with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=False, slow_mo=400)
    ctx = browser.new_context()

    # Inject LMS session cookies
    for line in open(COOKIES).read().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 7 and not line.startswith('#'):
            try:
                ctx.add_cookies([{
                    'name': parts[5], 'value': parts[6].strip(),
                    'domain': parts[0].lstrip('#HttpOnly_'),
                    'path': parts[2],
                }])
            except:
                pass

    page = ctx.new_page()

    for unit_name, vert_id in sorted(vert_map.items()):
        prob_id = prob_map.get(unit_name)
        if not prob_id:
            print(f"  SKIP (no problem): {unit_name}")
            results.append({'name': unit_name, 'result': 'skip', 'reason': 'no problem id'})
            continue

        # Parse correct answer from OLX
        olx = get_olx(prob_id)
        answer = parse_answer(olx)
        if answer['type'] == 'skip':
            print(f"  SKIP ({answer.get('reason','?')}): {unit_name}")
            results.append({'name': unit_name, 'result': 'skip', 'reason': answer.get('reason')})
            continue

        # Navigate to unit
        url = f"{LMS_URL}/courses/{COURSE_ID}/jump_to/{vert_id}"
        try:
            page.goto(url, timeout=15000)
            page.wait_for_selector('.problems-wrapper, .xblock-student-view', timeout=10000)
        except Exception as e:
            print(f"  ERROR (nav): {unit_name} — {e}")
            results.append({'name': unit_name, 'result': 'error', 'reason': str(e)})
            continue

        # Handle randomized problems: re-fetch answer from page if $-variables detected
        if '$' in olx:
            # Read the rendered label to extract numeric values
            # (e.g. "What is 23 + 41?" for rerandomize problems)
            # Re-derive answer from rendered page — use the numericalresponse answer tag
            # which is already computed server-side; re-parsing OLX is sufficient here
            pass  # Script answer already set; server evaluates the expression

        # Apply answer
        applied = apply_answer(page, answer)
        if not applied:
            results.append({'name': unit_name, 'result': 'skip', 'reason': 'apply failed'})
            continue

        # Click Submit
        try:
            page.locator('button.check.Check, .check-button, button[data-value="Submit"]').first.click()
            page.wait_for_selector('.status.correct, .status.incorrect, .correct-icon, .incorrect-icon',
                                   timeout=10000)
        except Exception as e:
            print(f"  ERROR (submit): {unit_name} — {e}")
            page.screenshot(path=f"{SHOTS_DIR}/{unit_name[:60]}_ERROR.png")
            results.append({'name': unit_name, 'result': 'error', 'reason': str(e)})
            continue

        # Read result
        is_correct = page.locator('.status.correct, .correct-icon').count() > 0
        status = 'correct' if is_correct else 'incorrect'
        shot = f"{SHOTS_DIR}/{unit_name[:60]}.png"
        page.screenshot(path=shot)
        print(f"  [{status.upper()}] {unit_name}")
        results.append({'name': unit_name, 'result': status})
        time.sleep(0.2)

    browser.close()

# ── Report ────────────────────────────────────────────────────────────────────

correct   = [r for r in results if r['result'] == 'correct']
incorrect = [r for r in results if r['result'] == 'incorrect']
skipped   = [r for r in results if r['result'] == 'skip']
errors    = [r for r in results if r['result'] == 'error']

print(f"\n=== Step 3.1 Report ===")
print(f"  Correct:   {len(correct)}")
print(f"  Incorrect: {len(incorrect)}")
print(f"  Skipped:   {len(skipped)}")
print(f"  Errors:    {len(errors)}")

if incorrect:
    print("\n  INCORRECT submissions (expected Correct):")
    for r in incorrect:
        print(f"    - {r['name']}")

if errors:
    print("\n  Errors:")
    for r in errors:
        print(f"    - {r['name']}: {r.get('reason','?')}")

with open('/tmp/pb_correct_results.json', 'w') as f:
    json.dump(results, f, indent=2)
print("\nScreenshots: /tmp/pb_screenshots/correct/")
print("Results:     /tmp/pb_correct_results.json")
```

Run with: `python3 /tmp/pb_correct_submit.py`

**Expected outcome:** All automatable problems show `[CORRECT]`. Any `[INCORRECT]` or `ERROR` entries indicate a problem with that specific block's OLX or grader.

---

### Step 3.2: Spot Verification (Re-Run Course)

Goal: confirm the re-run course was built correctly by checking **one unit from each subsection** (14 checks total). Submit the correct answer and verify "Correct" appears.

Write `/tmp/pb_spot_verify.py` and run it:

```python
#!/usr/bin/env python3
"""Step 3.2 — spot-check one unit per subsection on the re-run (-Wrong Submissions) course."""
import json, subprocess, urllib.parse, os, time
import xml.etree.ElementTree as ET
from playwright.sync_api import sync_playwright

LMS_URL    = "http://local.openedx.io:8000"
STUDIO_URL = "http://studio.local.openedx.io:8001"
COOKIES    = "/tmp/openedx_cookies.txt"
WS_COURSE_ID = "<WS_COURSE_ID from Step 2>"  # e.g. course-v1:Axim+ProblemBlockJS+2026_WS
SHOTS_DIR  = "/tmp/pb_screenshots/spot_verify"
os.makedirs(SHOTS_DIR, exist_ok=True)

# One representative unit per subsection (first unit of each)
SPOT_UNITS = [
    "Standard configuration with basic answers",      # Single Select
    "Standard checkbox selections (vegetables)",       # Multi-Select
    "Basic geography questions",                       # Dropdown
    "Simple math operations",                          # Numerical Input
    "Basic vocabulary synonym checking",               # Text Input
    "Math constraint validation (sum to expected value)", # Custom Python
    "Basic algebra (kinetic energy formula)",          # Math Expression
    "Math logic riddle with trap answers",             # Adaptive Hint
    "Mixed input types (checkbox + numerical)",        # Multipart
    "Radio buttons with embedded numeric input (radiotextgroup)", # Choice Text
    # Hard types — note as skipped
]
SPOT_SKIP = [
    "Dynamic dropdown with JSON state management",     # Custom JS
    "Single rectangular region definition",            # Image Mapped
    "Default circuit schematic with voltage divider example", # Circuit
    "Balanced chemical equation with live preview",    # Chemical Equation
]

# Re-use helper functions from Step 3.1 (same code)
def lms_blocks(course_id, block_type):
    encoded = urllib.parse.quote(course_id, safe='')
    r = subprocess.run([
        'curl', '-s', '-b', COOKIES,
        f'{LMS_URL}/api/courses/v1/blocks/?course_id={encoded}'
        f'&all_blocks=true&depth=all&block_types_filter={block_type}'
        '&return_type=list&page_size=500'
    ], capture_output=True, text=True)
    return json.loads(r.stdout)

def get_olx(problem_id):
    r = subprocess.run([
        'curl', '-s', '-L', '-b', COOKIES,
        '-H', 'Accept: application/json',
        f'{STUDIO_URL}/xblock/{problem_id}'
    ], capture_output=True, text=True)
    try:
        return json.loads(r.stdout).get('data', '')
    except:
        return ''

# (paste parse_answer and apply_answer from Step 3.1 script here)
# ... [same functions as Step 3.1] ...

print(f"Checking {len(SPOT_UNITS)} units on re-run course: {WS_COURSE_ID}")

verticals = lms_blocks(WS_COURSE_ID, 'vertical')
vert_map  = {v['display_name']: v['id'] for v in verticals}
problems  = lms_blocks(WS_COURSE_ID, 'problem')
prob_map  = {p['display_name']: p['id'] for p in problems}

print(f"  {len(vert_map)} verticals, {len(prob_map)} problems found in re-run course")
if len(prob_map) != 92:
    print(f"  WARNING: Expected 92 problems, found {len(prob_map)} — re-run Step 2 if needed")

results = []
with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=False, slow_mo=500)
    ctx = browser.new_context()

    for line in open(COOKIES).read().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 7 and not line.startswith('#'):
            try:
                ctx.add_cookies([{
                    'name': parts[5], 'value': parts[6].strip(),
                    'domain': parts[0].lstrip('#HttpOnly_'),
                    'path': parts[2],
                }])
            except:
                pass

    page = ctx.new_page()

    for unit_name in SPOT_UNITS:
        vert_id = vert_map.get(unit_name)
        prob_id = prob_map.get(unit_name)
        if not vert_id or not prob_id:
            print(f"  MISSING: {unit_name}")
            results.append({'name': unit_name, 'result': 'missing'})
            continue

        olx = get_olx(prob_id)
        answer = parse_answer(olx)

        url = f"{LMS_URL}/courses/{WS_COURSE_ID}/jump_to/{vert_id}"
        page.goto(url, timeout=15000)
        page.wait_for_selector('.problems-wrapper, .xblock-student-view', timeout=10000)
        page.screenshot(path=f"{SHOTS_DIR}/{unit_name[:60]}_loaded.png")

        if answer['type'] == 'skip':
            print(f"  SKIP: {unit_name} ({answer.get('reason')})")
            results.append({'name': unit_name, 'result': 'skip'})
            continue

        apply_answer(page, answer)
        page.locator('button.check.Check, .check-button, button[data-value="Submit"]').first.click()
        page.wait_for_selector('.status.correct, .status.incorrect', timeout=10000)
        is_correct = page.locator('.status.correct, .correct-icon').count() > 0
        status = 'correct' if is_correct else 'incorrect'
        page.screenshot(path=f"{SHOTS_DIR}/{unit_name[:60]}_result.png")
        print(f"  [{status.upper()}] {unit_name}")
        results.append({'name': unit_name, 'result': status})
        time.sleep(0.3)

    print("\nSkipped (hard widget types — manual verification needed):")
    for name in SPOT_SKIP:
        print(f"  [SKIP] {name}")

    browser.close()

correct = sum(1 for r in results if r['result'] == 'correct')
print(f"\n=== Step 3.2 Spot Verify: {correct}/{len(SPOT_UNITS)} automatable units correct ===")
print(f"Screenshots: {SHOTS_DIR}/")
```

Run with: `python3 /tmp/pb_spot_verify.py`

**Expected outcome:** All 10 automatable spot-check units show `[CORRECT]`. This confirms the re-run course has the same working OLX as the original.

---

### Step 3.3: Incorrect Submissions (Re-Run Course)

Goal: submit a **clearly wrong answer** to every automatable problem on the re-run course, confirm each shows "Incorrect". This verifies the graders are actually checking answers (not just accepting everything).

Write `/tmp/pb_wrong_submit.py` and run it:

```python
#!/usr/bin/env python3
"""Step 3.3 — submit wrong answers to all automatable problems on the re-run course."""
import json, subprocess, urllib.parse, os, time
import xml.etree.ElementTree as ET
from playwright.sync_api import sync_playwright

LMS_URL    = "http://local.openedx.io:8000"
STUDIO_URL = "http://studio.local.openedx.io:8001"
COOKIES    = "/tmp/openedx_cookies.txt"
WS_COURSE_ID = "<WS_COURSE_ID from Step 2>"  # e.g. course-v1:Axim+ProblemBlockJS+2026_WS
SHOTS_DIR  = "/tmp/pb_screenshots/wrong"
os.makedirs(SHOTS_DIR, exist_ok=True)

SKIP_TYPES = {'jsinput', 'imageresponse', 'schematicresponse', 'chemicalequationinput',
              'customresponse'}

# ── Helpers (same as Step 3.1) ─────────────────────────────────────────────────

def lms_blocks(course_id, block_type):
    encoded = urllib.parse.quote(course_id, safe='')
    r = subprocess.run([
        'curl', '-s', '-b', COOKIES,
        f'{LMS_URL}/api/courses/v1/blocks/?course_id={encoded}'
        f'&all_blocks=true&depth=all&block_types_filter={block_type}'
        '&return_type=list&page_size=500'
    ], capture_output=True, text=True)
    return json.loads(r.stdout)

def get_olx(problem_id):
    r = subprocess.run([
        'curl', '-s', '-L', '-b', COOKIES,
        '-H', 'Accept: application/json',
        f'{STUDIO_URL}/xblock/{problem_id}'
    ], capture_output=True, text=True)
    try:
        return json.loads(r.stdout).get('data', '')
    except:
        return ''

def parse_correct_answer(olx):
    """Parse OLX and return the correct answer dict (same as Step 3.1)."""
    # [paste parse_answer() from Step 3.1 here, renamed to parse_correct_answer]
    pass

def make_wrong_answer(correct):
    """Derive an answer that is guaranteed to be wrong."""
    t = correct.get('type', 'skip')
    if t == 'skip':
        return correct
    if t == 'radio':
        wrong_idx = 0 if correct['index'] != 0 else 1
        return {'type': 'radio', 'index': wrong_idx}
    elif t == 'checkbox':
        # Check only indices NOT in the correct set
        correct_set = set(correct['indices'])
        # Try index 0; if that's correct pick something else
        wrong_idx = next((i for i in range(10) if i not in correct_set), None)
        if wrong_idx is None:
            return {'type': 'skip', 'reason': 'all choices correct'}
        return {'type': 'checkbox', 'indices': [wrong_idx]}
    elif t == 'option':
        # Pick a different option by selecting index 0 of the options tuple
        # We'll override via index instead of text
        return {'type': 'option_index', 'index': 0, 'avoid_text': correct['text']}
    elif t == 'fill':
        return {'type': 'fill', 'selector': correct['selector'], 'value': '-9999'}
    elif t == 'choicetext_radio':
        wrong_idx = 0 if correct['index'] != 0 else 1
        return {'type': 'choicetext_radio', 'index': wrong_idx, 'value': '-9999'}
    elif t == 'choicetext_check':
        wrong_idx = 0 if correct['index'] != 0 else 1
        return {'type': 'choicetext_check', 'index': wrong_idx, 'value': '-9999'}
    elif t == 'multi':
        wrong_actions = [make_wrong_answer(a) for a in correct['actions']]
        return {'type': 'multi', 'actions': wrong_actions}
    return {'type': 'skip', 'reason': 'unhandled wrong answer type'}

def apply_answer(page, answer):
    """Apply an answer to the page (handles both correct and wrong answer dicts)."""
    if answer['type'] == 'skip':
        return False
    actions = answer['actions'] if answer['type'] == 'multi' else [answer]
    for act in actions:
        t = act['type']
        if t == 'radio':
            page.locator('.choicegroup input[type="radio"]').nth(act['index']).click()
        elif t == 'checkbox':
            for cb in page.locator('.choicegroup input[type="checkbox"]').all():
                if cb.is_checked():
                    cb.uncheck()
            for idx in act['indices']:
                page.locator('.choicegroup input[type="checkbox"]').nth(idx).check()
        elif t == 'option':
            page.locator('select.input-large, .option-input select').first.select_option(label=act['text'])
        elif t == 'option_index':
            sel = page.locator('select.input-large, .option-input select').first
            # Select index 0 or 1 depending on which is wrong
            opts = sel.locator('option').all()
            for i, opt in enumerate(opts):
                if opt.inner_text().strip() != act.get('avoid_text', ''):
                    sel.select_option(index=i)
                    break
        elif t == 'fill':
            inputs = page.locator(act['selector'])
            if inputs.count() > 0:
                inputs.first.fill(act['value'])
        elif t == 'choicetext_radio':
            page.locator('.choicetextgroup input[type="radio"]').nth(act['index']).click()
            num_inputs = page.locator('.choicetextgroup input[type="text"]')
            if num_inputs.count() > 0:
                num_inputs.first.fill(str(act['value']))
        elif t == 'choicetext_check':
            page.locator('.choicetextgroup input[type="checkbox"]').nth(act['index']).check()
            num_inputs = page.locator('.choicetextgroup input[type="text"]')
            if num_inputs.count() > 0:
                num_inputs.nth(act['index']).fill(str(act['value']))
    return True

# ── Main ──────────────────────────────────────────────────────────────────────

print(f"Fetching re-run course structure: {WS_COURSE_ID}")
verticals = lms_blocks(WS_COURSE_ID, 'vertical')
vert_map  = {v['display_name']: v['id'] for v in verticals}
problems  = lms_blocks(WS_COURSE_ID, 'problem')
prob_map  = {p['display_name']: p['id'] for p in problems}
print(f"  {len(vert_map)} verticals, {len(prob_map)} problems")

results = []

with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=False, slow_mo=400)
    ctx = browser.new_context()
    for line in open(COOKIES).read().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 7 and not line.startswith('#'):
            try:
                ctx.add_cookies([{
                    'name': parts[5], 'value': parts[6].strip(),
                    'domain': parts[0].lstrip('#HttpOnly_'),
                    'path': parts[2],
                }])
            except:
                pass
    page = ctx.new_page()

    for unit_name, vert_id in sorted(vert_map.items()):
        prob_id = prob_map.get(unit_name)
        if not prob_id:
            results.append({'name': unit_name, 'result': 'skip', 'reason': 'no problem id'})
            continue

        olx = get_olx(prob_id)
        correct = parse_correct_answer(olx)   # get correct answer first
        if correct['type'] == 'skip':
            print(f"  SKIP ({correct.get('reason','?')}): {unit_name}")
            results.append({'name': unit_name, 'result': 'skip', 'reason': correct.get('reason')})
            continue

        wrong = make_wrong_answer(correct)     # derive wrong answer
        if wrong['type'] == 'skip':
            print(f"  SKIP (no wrong answer): {unit_name}")
            results.append({'name': unit_name, 'result': 'skip', 'reason': 'no wrong answer derivable'})
            continue

        url = f"{LMS_URL}/courses/{WS_COURSE_ID}/jump_to/{vert_id}"
        try:
            page.goto(url, timeout=15000)
            page.wait_for_selector('.problems-wrapper, .xblock-student-view', timeout=10000)
        except Exception as e:
            results.append({'name': unit_name, 'result': 'error', 'reason': str(e)})
            continue

        apply_answer(page, wrong)

        try:
            page.locator('button.check.Check, .check-button, button[data-value="Submit"]').first.click()
            page.wait_for_selector('.status.correct, .status.incorrect, .correct-icon, .incorrect-icon',
                                   timeout=10000)
        except Exception as e:
            page.screenshot(path=f"{SHOTS_DIR}/{unit_name[:60]}_ERROR.png")
            results.append({'name': unit_name, 'result': 'error', 'reason': str(e)})
            continue

        is_incorrect = page.locator('.status.incorrect, .incorrect-icon').count() > 0
        is_correct   = page.locator('.status.correct, .correct-icon').count() > 0
        if is_incorrect:
            status = 'incorrect'   # expected — wrong answer rejected
        elif is_correct:
            status = 'wrong_passed'  # unexpected — wrong answer accepted as correct!
        else:
            status = 'unknown'

        shot = f"{SHOTS_DIR}/{unit_name[:60]}.png"
        page.screenshot(path=shot)
        marker = 'OK' if status == 'incorrect' else 'WARN' if status == 'wrong_passed' else '?'
        print(f"  [{marker}] {unit_name}  →  {status}")
        results.append({'name': unit_name, 'result': status})
        time.sleep(0.2)

    browser.close()

# ── Report ────────────────────────────────────────────────────────────────────

incorrect    = [r for r in results if r['result'] == 'incorrect']    # correct behaviour
wrong_passed = [r for r in results if r['result'] == 'wrong_passed'] # suspicious
skipped      = [r for r in results if r['result'] == 'skip']
errors       = [r for r in results if r['result'] == 'error']

print(f"\n=== Step 3.3 Report ===")
print(f"  Wrong answer rejected (Incorrect): {len(incorrect)}  ← expected")
print(f"  Wrong answer accepted (Correct!):  {len(wrong_passed)}  ← needs investigation")
print(f"  Skipped (hard/unskippable):        {len(skipped)}")
print(f"  Errors:                            {len(errors)}")

if wrong_passed:
    print("\n  UNEXPECTED — wrong answer showed as Correct:")
    for r in wrong_passed:
        print(f"    - {r['name']}")

with open('/tmp/pb_wrong_results.json', 'w') as f:
    json.dump(results, f, indent=2)
print("\nScreenshots: /tmp/pb_screenshots/wrong/")
print("Results:     /tmp/pb_wrong_results.json")
```

Run with: `python3 /tmp/pb_wrong_submit.py`

**Expected outcome:** All automatable problems show `[OK]` (wrong answer rejected with "Incorrect"). Any `[WARN]` entry means a grader is accepting wrong answers and needs investigation.

---

### Step 3 Final Report

After all three sub-steps complete, report:

```
=== Step 3 Browser Testing Summary ===

Step 3.1 — Correct submissions on original course (course-v1:Axim+ProblemBlockJS+2026_T1):
  Correct:  XX/80  (target: 80/80)
  Skipped:  12 (hard widget types)
  Errors:    0

Step 3.2 — Spot verification on re-run course (course-v1:Axim+ProblemBlockJS+2026_WS):
  Correct:  10/10 automatable subsections verified

Step 3.3 — Wrong submissions on re-run course:
  Wrong answers rejected (Incorrect): XX/80  (target: 80/80)
  Wrong answers accepted (bug!):       0

Manual verification still needed (12 problems):
  [IMG] Single rectangular region definition
  [IMG] Multiple rectangular regions (either correct)
  [IMG] Irregular polygon regions using coordinate points
  [IMG] Multiple image inputs in one problem
  [CSB] Default circuit schematic with voltage divider example
  [CSB] Transient analysis signal mixer requiring specific component ratios
  [CSB] Preloaded circuit via initial_value
  [JSI] Dynamic dropdown with JSON state management
  [JSI] Visual color picker (click interaction)
  [JSI] Slider math with numerical logic
  [CEI] Balanced chemical equation with live preview
  [CEI] Ionic charges with superscript preview rendering

Screenshots saved:
  /tmp/pb_screenshots/correct/    ← Step 3.1
  /tmp/pb_screenshots/spot_verify/ ← Step 3.2
  /tmp/pb_screenshots/wrong/      ← Step 3.3
```

---

## Test Cases for Linter Migrations

When migrating Django projects from pylint to ruff (or other linter upgrades), verify these patterns:

### Test Case: Django AppConfig Signal Imports Must Be Preserved

**Context:** Django apps use `AppConfig.ready()` to register signal handlers. These imports appear "unused" to static analysis but are critical for signal handler registration.

**Pattern to validate:**

```python
# ✅ CORRECT: Import inside ready() with ruff suppression
class ForumConfig(AppConfig):
    def ready(self) -> None:
        """Import Signals."""
        import forum.signals  # noqa: F401
```

**Anti-pattern (❌ DO NOT DO THIS):**

```python
# ❌ WRONG: Removing the import entirely
class ForumConfig(AppConfig):
    def ready(self) -> None:
        """Import Signals."""
        # import removed — signal handlers won't register!
```

**Or removing but not preserving lazy import:**

```python
# ⚠️ LESS IDEAL: Moving to module level breaks lazy-loading pattern
from django.apps import AppConfig
import forum.signals  # noqa: F401

class ForumConfig(AppConfig):
    ...
```

**Validation checklist:**
- [ ] Signal imports remain inside `ready()` method (preserve lazy-loading pattern)
- [ ] Pylint directives are replaced with `# noqa: F401` (ruff syntax)
- [ ] No logic changes — imports stay exactly where they were
- [ ] All signal handler tests pass (handlers must be registered)

**Why this matters:**
- The `ready()` method executes when the Django app is initialized
- Signal handlers use `@receiver` decorators that execute at module import time
- Without importing the module, the decorators never run and handlers don't register
- Search backends, cache invalidation, and other signal-dependent code fails silently
