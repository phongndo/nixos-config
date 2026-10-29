---
name: hillclimb
description: Trigger this if the user says 'hill climb'.
---

# Hill climb

Improve something by measuring it, changing it, and keeping only the changes
that measure better.

1. Define the score before you change anything: what you measure, how, the
   target that means done, and the budget. If the user did not say, propose
   them and ask once.
2. Measure the starting point.
3. Make one change and measure again. Keep it only if the score improved
   without breaking what worked. Otherwise undo it.
4. Log every try in an untracked `.hillclimb.tsv`: score, kept or undone, what
   you tried.
5. Repeat until the target holds, the budget runs out, or you are stuck.

Never change the score to pass. Do not ask whether to continue. If your context
resets, read the log and continue.

When you stop, report why, the starting and final scores, and what you kept.
