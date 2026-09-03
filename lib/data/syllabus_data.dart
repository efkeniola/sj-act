import '../models/models.dart';

class SyllabusTopic {
  final String id;
  final ActSection section;
  final String skillArea;
  final String title;
  final String summary;
  final String tip;        // improvement tip
  final String advice;     // deeper advice for weak students
  final List<String> keyPoints;

  const SyllabusTopic({
    required this.id,
    required this.section,
    required this.skillArea,
    required this.title,
    required this.summary,
    required this.tip,
    required this.advice,
    required this.keyPoints,
  });
}

const List<SyllabusTopic> syllabusTopics = [
  // ── ENGLISH ──────────────────────────────────────────────────────────────
  SyllabusTopic(
    id: 'en-conv-01',
    section: ActSection.english,
    skillArea: 'Conventions of Standard English',
    title: 'Punctuation: Commas, Semicolons, Colons',
    summary:
        'Mastery of when and how to use commas, semicolons, colons, dashes, and apostrophes in standard written English.',
    tip:
        'Learn the six comma rules, one at a time. The most tested: (1) after introductory clauses, (2) between items in a list, (3) before coordinating conjunctions in compound sentences.',
    advice:
        'If commas are your weakness, write out the six comma rules on a card and review them daily. Then practice by identifying which rule justifies each comma in a passage before looking at answer choices. The ACT tests comma misuse more than any other punctuation error.',
    keyPoints: [
      'Semicolons join two independent clauses (no conjunction needed)',
      'Colons must follow a complete sentence before introducing a list or explanation',
      'Do not use a comma between subject and verb',
      'Use a comma before FANBOYS (for, and, nor, but, or, yet, so) in compound sentences',
    ],
  ),
  SyllabusTopic(
    id: 'en-conv-02',
    section: ActSection.english,
    skillArea: 'Conventions of Standard English',
    title: 'Subject-Verb Agreement',
    summary:
        'Identifying and correcting subject-verb agreement errors, especially with intervening phrases, collective nouns, and compound subjects.',
    tip:
        'Always identify the true subject before checking verb agreement. Cross out prepositional phrases and relative clauses between the subject and verb — the verb must agree with the simple subject, not the nearest noun.',
    advice:
        'Subject-verb agreement errors are easy to miss when a long phrase separates subject from verb. Train yourself to always ask "What is the subject?" before evaluating the verb. Intervening phrases like "along with," "as well as," and "in addition to" do NOT make a singular subject plural.',
    keyPoints: [
      'Collective nouns (team, committee, jury) take singular verbs in American English',
      'Indefinite pronouns (each, every, either, neither) take singular verbs',
      'Compound subjects joined by "or/nor" agree with the nearer subject',
      'Inverted sentences: the subject follows the verb; identify it carefully',
    ],
  ),
  SyllabusTopic(
    id: 'en-conv-03',
    section: ActSection.english,
    skillArea: 'Conventions of Standard English',
    title: 'Modifiers and Parallel Structure',
    summary:
        'Identifying dangling/misplaced modifiers and ensuring parallel structure in lists and comparisons.',
    tip:
        'For modifier questions: identify what is doing the action in the modifying phrase, then make sure that noun/pronoun immediately follows the phrase. For parallelism: list items must all be the same grammatical form.',
    advice:
        'Dangling modifiers are one of the ACT\'s favorite traps. The instant you see a sentence beginning with a participial phrase ("-ing" or "-ed"), ask yourself: "Who or what is doing this action?" — that entity must be the sentence\'s subject.',
    keyPoints: [
      'Opening participial phrases must modify the subject of the main clause',
      'Parallel items in a list must share the same grammatical form (noun, verb, etc.)',
      'Comparisons must be parallel: compare nouns to nouns, ideas to ideas',
      'Avoid double negatives and redundant expressions ("return back", "end result")',
    ],
  ),
  SyllabusTopic(
    id: 'en-prod-01',
    section: ActSection.english,
    skillArea: 'Production of Writing',
    title: 'Organization and Logical Sequence',
    summary:
        'Determining the most logical order of sentences and paragraphs, and adding/deleting/moving content to improve coherence.',
    tip:
        'Read all options before deciding on sentence order. Look for signal words (first, then, however, therefore, finally) that indicate logical sequence. The opening sentence should introduce the topic; the closing sentence should provide a conclusion or transition.',
    advice:
        'When asked whether to add, delete, or keep a sentence, always ask: "Does this sentence support the paragraph\'s main idea?" Extra information that is true but irrelevant to the paragraph\'s focus should be deleted. Irrelevant does NOT mean inaccurate — it means off-topic.',
    keyPoints: [
      'Transitional words signal logical relationships (contrast, cause/effect, sequence)',
      'Each paragraph should have one clear main idea',
      'Deleting a sentence is correct when it is off-topic, redundant, or interrupts flow',
      'Adding a sentence is correct when it fills a logical gap in the argument',
    ],
  ),
  SyllabusTopic(
    id: 'en-lang-01',
    section: ActSection.english,
    skillArea: 'Knowledge of Language',
    title: 'Style, Tone, and Conciseness',
    summary:
        'Selecting words and phrases that match the passage\'s style and tone, and eliminating wordiness and redundancy.',
    tip:
        'When two answers are grammatically correct, the shorter one is almost always correct on the ACT. Avoid options that use more words to say the same thing ("due to the fact that" vs "because").',
    advice:
        'The ACT strongly favors concise, precise language. Learn to spot redundant phrases: "past history" (history is already past), "completely finished," "end result." Also watch for phrases that change the passage\'s formal tone — always match the style of the surrounding text.',
    keyPoints: [
      'Eliminate redundancy: do not say the same thing twice in different words',
      'Prefer active voice over passive voice for clarity',
      'Formal vs informal language must match the passage\'s overall register',
      'Avoid wordy phrases: "in spite of the fact that" → "although"',
    ],
  ),

  // ── MATHEMATICS ───────────────────────────────────────────────────────────
  SyllabusTopic(
    id: 'ma-alg-01',
    section: ActSection.math,
    skillArea: 'Algebra',
    title: 'Linear Equations and Inequalities',
    summary:
        'Solving one-variable and multi-variable linear equations and inequalities, including word problems.',
    tip:
        'Set up equations from word problems by identifying the unknown first, then writing an equation that describes the relationship. For inequalities, flip the inequality sign when multiplying or dividing by a negative number.',
    advice:
        'Many students lose points on word-problem setup, not computation. Read the problem twice: once for context, once to identify what mathematical relationship is being described. Assign a variable, write the equation, then solve.',
    keyPoints: [
      'Flip inequality when multiplying/dividing by a negative number',
      'Systems of equations: substitution or elimination',
      'Absolute value equations produce two solutions',
      'Linear inequalities on a number line: open circle for < >, closed for ≤ ≥',
    ],
  ),
  SyllabusTopic(
    id: 'ma-alg-02',
    section: ActSection.math,
    skillArea: 'Algebra',
    title: 'Quadratic Equations and Polynomials',
    summary:
        'Factoring quadratics, applying the quadratic formula, and working with polynomial expressions.',
    tip:
        'Know three methods for solving quadratics: (1) factoring, (2) completing the square, (3) quadratic formula. Factoring is fastest when it works. The discriminant (b²-4ac) tells you about solutions before you solve.',
    advice:
        'If you cannot factor quickly, go straight to the quadratic formula — it always works. Memorize: x = (-b ± √(b²-4ac)) / 2a. Practice recognizing the "nice" factorable cases vs when to use the formula.',
    keyPoints: [
      'Difference of squares: a² - b² = (a+b)(a-b)',
      'Perfect square trinomials: a² + 2ab + b² = (a+b)²',
      'Discriminant: positive = 2 real solutions, zero = 1, negative = no real solutions',
      'Sum/product of roots: sum = -b/a, product = c/a',
    ],
  ),
  SyllabusTopic(
    id: 'ma-func-01',
    section: ActSection.math,
    skillArea: 'Functions',
    title: 'Functions: Evaluation, Composition, and Inverse',
    summary:
        'Evaluating functions, composing functions, finding inverse functions, and interpreting function graphs.',
    tip:
        'For f(g(x)), work inside-out: compute g(x) first, then input that result into f. For inverse functions, swap x and y, then solve for y.',
    advice:
        'Function notation trips up many students. f(2) means "substitute x = 2 into f" — it does NOT mean "f times 2." Composition f(g(x)) is also confusing: g runs first, then f. Think of it as an assembly line.',
    keyPoints: [
      'Domain: all valid input values (x); Range: all possible output values (y)',
      'Vertical line test: a graph represents a function if each x has only one y',
      'For inverse: swap (x,y) pairs; the graph reflects over y = x',
      'Transformations: f(x)+k shifts up, f(x+k) shifts left, -f(x) reflects over x-axis',
    ],
  ),
  SyllabusTopic(
    id: 'ma-geom-01',
    section: ActSection.math,
    skillArea: 'Geometry',
    title: 'Triangles, Circles, and Coordinate Geometry',
    summary:
        'Properties of triangles (including special right triangles), circle theorems, and coordinate geometry formulas.',
    tip:
        'For the ACT, always have these formulas ready without the formula sheet: distance formula, midpoint formula, slope formula, and the area formulas for common shapes. The ACT does NOT provide a formula sheet.',
    advice:
        'Unlike the SAT, the ACT does not give you a formula reference sheet. You must memorize all key geometry formulas. Start with: area of circle (πr²), circumference (2πr), area of triangle (½bh), and the coordinate geometry formulas.',
    keyPoints: [
      '30-60-90 triangle: sides in ratio 1 : √3 : 2',
      '45-45-90 triangle: sides in ratio 1 : 1 : √2',
      'Circle: arc length = (central angle / 360°) × 2πr',
      'Slope of a line: m = (y₂-y₁)/(x₂-x₁)',
    ],
  ),
  SyllabusTopic(
    id: 'ma-stat-01',
    section: ActSection.math,
    skillArea: 'Statistics and Probability',
    title: 'Data Analysis and Probability',
    summary:
        'Interpreting data displays (charts, tables, scatterplots), computing statistics (mean, median, mode), and calculating probabilities.',
    tip:
        'For mean/median confusion: mean = sum ÷ count; median = middle value when sorted. The ACT frequently asks which measure is more resistant to outliers — always median (not mean).',
    advice:
        'Statistics questions on the ACT are often about reading data correctly, not complex calculations. Make sure you are reading the right row/column/bar before computing. Label your data when re-reading a table.',
    keyPoints: [
      'Probability = favorable outcomes ÷ total outcomes',
      'Independent events: P(A and B) = P(A) × P(B)',
      'Complementary events: P(not A) = 1 - P(A)',
      'Expected value: sum of (value × probability) for all outcomes',
    ],
  ),

  // ── READING ───────────────────────────────────────────────────────────────
  SyllabusTopic(
    id: 're-key-01',
    section: ActSection.reading,
    skillArea: 'Key Ideas and Details',
    title: 'Main Idea and Central Theme',
    summary:
        'Identifying the central idea or argument of a passage and distinguishing it from supporting details.',
    tip:
        'The main idea is never too specific (a detail) or too broad (an assumption not in the text). It must be something the author actually discusses throughout the passage, supported by most of the text.',
    advice:
        'Test each "main idea" option against the entire passage: if an option is only discussed in one paragraph, it is probably a detail, not the main idea. The correct main idea encompasses the whole passage.',
    keyPoints: [
      'Main idea vs supporting detail: main idea runs through the whole passage',
      'Author\'s purpose: to inform, persuade, entertain, or describe',
      'Evidence must be explicitly stated — avoid reading extra meaning into the text',
      'Distinguish between what the text says vs what you personally believe',
    ],
  ),
  SyllabusTopic(
    id: 're-craft-01',
    section: ActSection.reading,
    skillArea: 'Craft and Structure',
    title: 'Author\'s Purpose and Point of View',
    summary:
        'Analyzing why an author made specific choices about structure, tone, and language, and identifying point of view.',
    tip:
        'For purpose questions, ask: "Why did the author include this?" not "What does this say?" The answer should describe an authorial intent, not restate content.',
    advice:
        'Point-of-view questions require you to identify who is speaking, what their perspective is, and what biases or assumptions they may carry. The ACT\'s literary fiction passages (often from novels) particularly test this skill.',
    keyPoints: [
      'Rhetorical purpose: each paragraph serves a function (evidence, counterargument, illustration)',
      'Tone words: objective, subjective, ironic, nostalgic, critical, celebratory',
      'Diction (word choice) reveals attitude — note emotionally loaded words',
      'Structural choices: why does the author begin/end with this particular content?',
    ],
  ),

  // ── SCIENCE ───────────────────────────────────────────────────────────────
  SyllabusTopic(
    id: 'sc-data-01',
    section: ActSection.science,
    skillArea: 'Interpretation of Data',
    title: 'Reading and Interpreting Data Displays',
    summary:
        'Accurately reading tables, graphs, and diagrams; identifying trends, comparisons, and relationships in scientific data.',
    tip:
        'Always read axis labels and units before interpreting any graph. The ACT frequently uses unfamiliar scientific contexts — you do not need to know the science; you need to read the data accurately.',
    advice:
        'The ACT Science section tests data literacy more than science knowledge. Practice reading graphs methodically: (1) title, (2) axes/labels/units, (3) what the data shows, (4) the range and scale. Only then look at the questions.',
    keyPoints: [
      'Positive correlation: both variables increase together',
      'Negative correlation: as one increases, the other decreases',
      'Interpolation: estimating within the range of data (valid)',
      'Extrapolation: estimating outside the range of data (less reliable)',
    ],
  ),
  SyllabusTopic(
    id: 'sc-invest-01',
    section: ActSection.science,
    skillArea: 'Scientific Investigation',
    title: 'Experimental Design and Variables',
    summary:
        'Understanding the structure of experiments, including independent/dependent variables, controls, and sources of error.',
    tip:
        'Independent variable = what the experimenter changes. Dependent variable = what is measured as a result. Control = the baseline kept constant. If asked "what is kept constant," look for variables mentioned as unchanged.',
    advice:
        'ACT experiment questions are predictable: they almost always ask about variables, controls, or how to improve the experiment. Learn to identify these quickly and you will handle most investigation questions in under 30 seconds.',
    keyPoints: [
      'Control group: same as experimental group except for the variable being tested',
      'A fair test changes only one variable at a time',
      'Sample size affects reliability: larger samples = more reliable results',
      'Sources of error: measurement error, sampling bias, equipment precision',
    ],
  ),
  SyllabusTopic(
    id: 'sc-eval-01',
    section: ActSection.science,
    skillArea: 'Evaluation of Models, Inferences, and Experimental Results',
    title: 'Conflicting Viewpoints and Scientific Claims',
    summary:
        'Comparing competing scientific hypotheses and evaluating evidence that supports or contradicts each.',
    tip:
        'In conflicting viewpoints passages, summarize each scientist\'s main claim in one sentence before reading the questions. Then, for each question, determine which scientist\'s specific claim is being tested.',
    advice:
        'Conflicting viewpoints are the hardest ACT Science passage type for most students. The key skill is keeping multiple hypotheses separate in your mind. Write a quick 1-line summary of each viewpoint, then evaluate each piece of evidence against those summaries.',
    keyPoints: [
      'Identify the core difference between the two viewpoints',
      'Strengthening evidence supports the mechanism proposed by that scientist',
      'Weakening evidence contradicts their proposed mechanism or explains results another way',
      'New data that is irrelevant to either hypothesis neither strengthens nor weakens either claim',
    ],
  ),
];

List<SyllabusTopic> topicsForSection(ActSection section) {
  return syllabusTopics.where((t) => t.section == section).toList();
}
