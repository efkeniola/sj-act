# ACT Question Generation Prompt
# Use this prompt to generate new questions and paste them into questions_data.dart

---

## Prompt to Generate ACT Questions

Use this exact prompt when asking an AI to generate questions:

---

Generate [NUMBER] ACT-style questions for the **[SECTION]** section.

Section options: English / Mathematics / Reading / Science

**Strict requirements — follow every rule exactly:**

1. **Format**: Return ONLY valid Dart code. Each question must be a `const ActQuestion(...)` object.

2. **IDs**: Use the format `[section_prefix]-[setNumber]-[2-digit index]`:
   - English: `en-2-01`, `en-2-02` etc.
   - Math: `ma-2-01`, `ma-2-02` etc.
   - Reading: `re-2-01` etc.
   - Science: `sc-2-01` etc.
   - Increment setNumber for new sets (set 1 already exists, use set 2)

3. **Section enum**: Use `ActSection.english` / `ActSection.math` / `ActSection.reading` / `ActSection.science`

4. **Skill areas** — use ONLY these exact strings:
   - English: `'Conventions of Standard English'` | `'Production of Writing'` | `'Knowledge of Language'`
   - Math: `'Algebra'` | `'Functions'` | `'Geometry'` | `'Statistics and Probability'` | `'Number and Quantity'`
   - Reading: `'Key Ideas and Details'` | `'Craft and Structure'` | `'Integration of Knowledge and Ideas'`
   - Science: `'Interpretation of Data'` | `'Scientific Investigation'` | `'Evaluation of Models, Inferences, and Experimental Results'`

5. **Difficulty**: `Difficulty.easy` | `Difficulty.medium` | `Difficulty.hard`

6. **Options**: Exactly 4 options in a `const List<String>`.

7. **Correct answer**: One of `'A'`, `'B'`, `'C'`, `'D'` — must match the correct option.

8. **Explanation**: At least 2 sentences explaining WHY the correct answer is right and WHY the wrong answers are wrong.

9. **Topic tip**: A concrete, actionable study tip for this specific skill area. 2–4 sentences. Must be different from the explanation.

10. **Reading / Science passages**: Include a `passageText` field with a realistic passage (150–300 words for Reading, data table or experimental description for Science).

11. **No emojis** anywhere in the output.

12. **Real ACT format**: Questions must match the actual difficulty and style of the official ACT test. Do not make questions too easy or obviously wrong.

13. **setNumber**: Use `2` (since set 1 already exists).

**Example output format:**
```dart
ActQuestion(
  id: 'ma-2-01',
  setNumber: 2,
  section: ActSection.math,
  skillArea: 'Algebra',
  difficulty: Difficulty.medium,
  questionText: 'If 5(x - 2) = 3x + 8, what is the value of x?',
  options: ['5', '6', '7', '9'],
  correctAnswer: 'D',
  explanation:
      '5(x-2) = 3x + 8 → 5x - 10 = 3x + 8 → 2x = 18 → x = 9. '
      'Options A, B, and C result from common arithmetic errors such as '
      'incorrect distribution or sign errors.',
  topicTip:
      'When solving linear equations, distribute first, then collect variable terms '
      'on one side and constants on the other. Always substitute your answer back '
      'into the original equation to verify.',
),
```

Generate the questions now. Output ONLY the Dart `ActQuestion(...)` objects — no surrounding list brackets, no imports, no comments.

---

## After generating, add to questions_data.dart:

```dart
const List<ActQuestion> mathSet2 = [
  // paste generated questions here
];
```

Then add to `allQuestionsSet1` map (or create `allQuestionsSet2`):
```dart
Map<ActSection, List<ActQuestion>> allQuestionsSet2 = {
  ActSection.math: mathSet2,
  // ...
};
```

And update `questionsForSection()` to include all sets:
```dart
List<ActQuestion> questionsForSection(ActSection section) {
  final set1 = allQuestionsSet1[section] ?? [];
  final set2 = allQuestionsSet2[section] ?? [];
  return [...set1, ...set2];
}
```
