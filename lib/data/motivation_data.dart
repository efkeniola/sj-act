/// Time-of-day motivational messages for the ACT prep app.
/// These are discipline-focused, concise, and academic in tone.
/// {name} is replaced with the user's display name at render time.
/// No emojis — matches the ACT's serious, professional brand.
library motivation_data;

const List<String> morningMotivations = [
  "Good morning, {name}. Consistency at this hour is what separates the students who improve from the ones who don't.",
  "{name}, a 36 isn't luck. It's what happens when someone starts their session before the distractions do.",
  "The ACT rewards disciplined preparation, {name}. Today's session is another brick in that foundation.",
  "{name}, you have the same 24 hours as every other student aiming for a top score. Use this one well.",
  "Most students wait until they feel ready. The ones who score in the 99th percentile practice whether they feel ready or not, {name}.",
  "{name}, your competition is also awake right now. The question is whether you are working.",
  "Morning practice cements what you learned the night before, {name}. Start with your weakest section.",
  "{name}, on test day, your brain will default to what it has practiced most. Make that count.",
  "A 1-point improvement on your composite score doesn't happen in one session, {name} — it happens in sessions exactly like this one.",
  "{name}, pick up where you left off. Progress is measured in weeks, not in single mornings.",
  "The students who score a 34 or higher are not more intelligent, {name} — they are more prepared. Start now.",
  "Good morning, {name}. No test score has ever improved by skipping a study session.",
  "{name}, hard questions do not become easier by avoiding them. Open your weakest section and go.",
  "Every correct answer you practice today is a reflex you are building for the real test, {name}.",
  "{name}, your score goal is achievable. Achievable requires this session. Begin.",
];

const List<String> afternoonMotivations = [
  "{name}, the afternoon is where momentum is either kept or lost. Stay with your plan.",
  "You're midday, {name}. A short focused session now is worth more than a long distracted one later.",
  "{name}, fatigue is not an excuse — it's a variable to manage. A brisk 20 minutes of practice counts.",
  "The ACT is four sections, {name}. If you haven't covered all four this week, now is the time.",
  "{name}, review the last question you got wrong. Understanding one error is more valuable than answering ten easy questions.",
  "Afternoon practice, {name}. The test itself is administered in the morning — train your brain to be sharp at that hour too.",
  "{name}, if you feel like skipping today, that's the exact moment to do 10 questions instead of zero.",
  "Progress tracking matters, {name}. Log this session. Students who track their accuracy improve faster.",
  "{name}, pick the topic you've been avoiding. That avoidance is costing you points.",
  "One section at a time, {name}. You don't have to solve every weakness today — just work on one.",
  "{name}, a score report showing growth is built from hundreds of small sessions like this one.",
  "Keep your study session active, not passive, {name}. Read explanations, don't just skim them.",
];

const List<String> eveningMotivations = [
  "{name}, end today the same way top scorers end every day — with a review of what you got wrong.",
  "Evening session, {name}. Go over your errors from earlier today while they're still fresh.",
  "{name}, strong ACT scores come from identifying patterns in your mistakes, not just more practice.",
  "Before you close the app tonight, {name} — review the tip for your weakest topic.",
  "{name}, tomorrow's confidence is built tonight. One focused session before bed goes a long way.",
  "The best use of an evening session, {name}: review explanations, not new questions.",
  "{name}, your accuracy this week — do you know what it is? Open your progress dashboard and find out.",
  "Evening is when the mind consolidates, {name}. A light review session cements what you practiced today.",
  "{name}, you don't need a perfect session tonight. You need a productive one. That's different.",
  "Log your score trend, {name}. Progress isn't always visible day to day — look at the weekly view.",
  "{name}, the students who score at the top review their wrong answers every single time. Do the same tonight.",
  "Good evening, {name}. What section felt hardest today? Spend 10 minutes on that topic before you stop.",
];

const List<String> weekendMotivations = [
  "{name}, dedicated test-takers use weekends differently than others. This is your chance to catch up or pull ahead.",
  "Weekends are not rest days from preparation, {name} — they are full-length practice opportunity days.",
  "{name}, if the ACT were next Saturday, would you feel ready? Today is a chance to change that answer.",
  "No school, no schedule, {name} — full availability for your highest-stakes practice session of the week.",
  "{name}, a strong weekend session can bring your composite score up faster than five short weekday sessions.",
  "The students scoring 34-36, {name}, spend their weekends practicing. That's one data point worth considering.",
  "{name}, take a full-length section with the real timing today. No shortcuts — that's how you build test-day stamina.",
];

String getMotivation(String name) {
  final hour = DateTime.now().hour;
  final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
  final weekday = DateTime.now().weekday; // 6 = Saturday, 7 = Sunday

  List<String> pool;
  if (weekday == 6 || weekday == 7) {
    pool = weekendMotivations;
  } else if (hour < 12) {
    pool = morningMotivations;
  } else if (hour < 18) {
    pool = afternoonMotivations;
  } else {
    pool = eveningMotivations;
  }

  final msg = pool[dayOfYear % pool.length];
  return msg.replaceAll('{name}', name);
}
