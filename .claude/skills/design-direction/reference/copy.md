# Copy (microcopy & voice)

Design is half typesetting, half writing. Bad copy makes good UI look amateur.

## Buttons are verbs

- ✅ "Save changes"
- ✅ "Create project"
- ✅ "Send invitation"
- ❌ "Submit"
- ❌ "OK"
- ❌ "Continue" (continue to what?)

The button label should answer "what will happen if I click this." If it's destructive, say so: "Delete account" not "Confirm."

## Empty states explain the next action

```
[icon]
No projects yet.

Projects let you group documents, share with teammates,
and track activity in one place.

[Create your first project]   [Learn more]
```

Bad version: "No items." — leaves the user nowhere.

## Error messages explain what to do

- ❌ "Invalid input."
- ❌ "Error code 42."
- ✅ "Email address is missing the @ symbol."
- ✅ "Couldn't connect — check your internet and try again."

Errors say: (1) what went wrong, (2) how to fix it.

## Loading copy is specific

- ❌ "Loading..."
- ✅ "Generating preview..."
- ✅ "Uploading 3 of 12 files..."
- ✅ "Searching across 142 documents..."

The specificity tells the user the system is alive and working on *their* thing.

## Confirmation language

For destructive actions:

```
Delete this draft?

This will permanently remove "Q4 Strategy v2" and its
17 revisions. This can't be undone.

[Cancel]   [Delete draft]
```

The destructive button is on the right, colored, but the warning is in the body. Confirming should require reading.

For non-destructive but consequential actions, single-tap is fine. Don't add a "Are you sure?" dialog to every action.

## Form labels

- Always present. "Email address" above the input, not in the placeholder.
- Placeholder is for examples: "you@example.com".
- Helper text below the input for hints. ("Use a work email.")
- Validation message replaces helper text when there's a problem.

## Voice consistency

Pick a voice in the brand-spec (step 1 of the workflow):

- **Authoritative** — "Your data is encrypted at rest." Used by enterprise/legal.
- **Friendly** — "We've got your back — your data is encrypted." Used by consumer SaaS.
- **Playful** — "Locked up tight 🔒 (well, 256-bit AES, but who's counting)." Used by toys, kids apps.
- **Plain** — "Encrypted at rest with 256-bit AES." Used by dev tools.

Don't mix. A "friendly" empty state and an "authoritative" error message read as written by two different people.

## Numbers and dates

- **Money** — show currency: "$12,450" or "USD 12,450". Tabular numbers.
- **Dates** — "Apr 15, 2026" beats "04/15/2026" beats "15/04/2026". Avoid format ambiguity.
- **Times** — "2:30 PM" or "14:30" depending on locale. Show timezone if it matters.
- **Relative time** — "2 hours ago" for recent, switch to absolute date after 7 days.
- **Counts** — "3 invites sent" not "(3) invites sent" or "3 invites have been sent."

## Anti-patterns

- **"Click here."** Always link the verb phrase: "Read the docs" not "Read more [here]."
- **Title Case Everywhere.** Sentence case is friendlier and easier to read. Title Case for product names and headlines only.
- **ALL CAPS BUTTONS.** Rare, on purpose, and with letter-spacing. Default to sentence case.
- **Marketing voice in UI.** "Unlock powerful insights with our AI engine!" belongs on the landing page, not on the dashboard's empty state.
- **Apologizing constantly.** "Oops, something went wrong, we're sorry!" — once, in the right place. Not as the default empty state copy.
