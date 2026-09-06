# Panels+ Translation Issue Template

---

You can check an example of how a translation issue looks like here:

> https://github.com/KristanLaimon/PanelsPlus/issues/3

## Part 1: Instructions & Placeholder Guide

1. Copy the Markdown template block from **Part 2** below.
2. Go to [GitHub Issues](https://github.com/KristanLaimon/BetterPanels/issues) and click **New Issue**.
3. Apply the **`translation`** label/tag when submitting your issue.
4. Replace the `<placeholder>` fields in your issue with your information using the reference table below:

### Placeholder Explanations & Examples

| Placeholder | Meaning | Example |
| :--- | :--- | :--- |
| `<LANGUAGE_NAME>` | The full name of the language | `French`, `German`, `Japanese`, `Simplified Chinese` |
| `<LANGUAGE_CODE>` | The KOReader / ISO locale code | `fr`, `de`, `ja`, `zh_CN` |
| `<YOUR_NAME_OR_HANDLE>` | Your name or GitHub handle to credit in release notes | `@john_doe` or `Jane Doe` |
| `<PASTE_PO_FILE_CONTENT_HERE>` | Here drag & drop your `.po` file into the issue comment (rename it to `.po.txt`, so it can be uploaded) | `msgid "Comic mode"\nmsgstr "Modo cómic"` |
| `<ADD_ANY_NOTES_OR_QUESTIONS_HERE>` | Optional notes, context, or questions for maintainers | *"Translated 'Comic mode' as 'Modo cómic' to match standard KOReader UI."* |

---

## Part 2: Copy & Paste Template

Copy the block below and paste it directly into your GitHub issue:

```markdown
### Translation <LANGUAGE_NAME>

### Language Details
- **Language Name**: <LANGUAGE_NAME>
- **Language Code**: <LANGUAGE_CODE>
- **Contribution Type**:
    - [ ] New Translation
    - [ ] Update Existing
- **Contributor Credit**: @<YOUR_NAME_OR_HANDLE>

### Translation File
<!-- Drag & drop your completed .po file here, or paste PO strings in the code block below -->
<!-- (Drag and drop your .po file, renamed to <LANGUAGE_CODE>.po.txt) due to github policies -->
`<PASTE_PO_FILE_CONTENT_HERE>`

### Additional Notes
<ADD_ANY_NOTES_OR_QUESTIONS_HERE... or delete this section if no notes>
```
