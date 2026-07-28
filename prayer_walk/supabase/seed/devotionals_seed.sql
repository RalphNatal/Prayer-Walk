-- ===========================================================================
-- SEED — run once, by hand, by the maintainer. NOT a migration.
-- ===========================================================================
--
-- Same bargain as `scripture_prompts_seed.sql`: this is content, not schema. It
-- lives outside `supabase/migrations/` because a migration must be safe to
-- re-run on every project, whereas this is a starting shelf an admin is
-- expected to edit, extend and prune from the console afterwards. Paste it into
-- the Supabase SQL editor after `20260728020000_devotionals.sql` has been
-- applied.
--
-- It is idempotent — a devotional with the same title is skipped — so running
-- it twice does not duplicate the shelf.
--
-- LICENSING
-- ---------
-- Every passage quoted below is the World English Bible, British Edition
-- (WEBBE): public domain, no licence fee, no attribution obligation. Re-pull
-- from https://ebible.org/webbe/ if byte-exact text matters to you.
--
-- Nothing here is drawn from the NIV, ESV, NLT, NASB or CSB. Those are
-- copyrighted and may not be redistributed in an app without a paid licence.
-- If you add a devotional from the console, quote WEBBE or quote nothing.
--
-- `author_id` is left null and `author_name` reads 'Prayer Walk': these were
-- not written by anyone with an account on this instance. Anything an admin
-- writes from the console carries their own name and id.

insert into public.devotionals
  (title, summary, body, scripture_ref, scripture_text,
   category, author_name, read_minutes, is_published, published_at)
select
  v.title, v.summary, v.body, v.scripture_ref, v.scripture_text,
  v.category, 'Prayer Walk', v.read_minutes, true, now()
from (values

  -- ---------------------------------------------------------- morning light --
  ('Before the street wakes',
   'A short prayer for the first hundred steps of the day.',
   E'Begin before you have decided anything. Step out, and let the first hundred steps be given away rather than used.\n\nNotice the sound your feet make. Notice that you did not have to ask for this morning; it arrived while you slept.\n\nWhen the noise starts — the first engine, the first shutter going up — do not resent it. Pray for whoever is behind it.',
   'Lamentations 3:22-23',
   'It is because of the LORD''s loving kindnesses that we are not consumed, because his compassion doesn''t fail. They are new every morning. Great is your faithfulness.',
   'morningLight', 2),

  -- -------------------------------------------------------------- gratitude --
  ('Count five things on this street',
   'Gratitude at walking pace, one block at a time.',
   E'Pick a block you know too well to see. Walk it slowly and find five things you have never thanked anyone for.\n\nThe tree someone planted before you were born. The light that works. The person who sweeps this corner at four in the morning.\n\nSay each one out loud if you can. Gratitude that stays in the head tends to evaporate.',
   'Psalm 118:24',
   'This is the day that the LORD has made. We will rejoice and be glad in it.',
   'gratitude', 3),

  ('Thanks on the way home',
   'The walk back is the half most people waste.',
   E'You have already done the thing you set out to do. The walk home is not admin — it is the only unhurried stretch of the day you are likely to get.\n\nName what went right. Not what you achieved: what was handed to you. There is a difference, and walking is slow enough to feel it.\n\nIf nothing comes, say so plainly. An honest empty hand is still a hand held out.',
   '1 Thessalonians 5:16-18',
   'Always rejoice. Pray without ceasing. In everything give thanks, for this is the will of God in Christ Jesus towards you.',
   'gratitude', 2),

  -- ----------------------------------------------------------- intercession --
  ('Carry one name the whole way',
   'One person, one route. Set them down only at the end.',
   E'Choose one name before you start. Not a list — one.\n\nEvery time your mind wanders, and it will, come back to the name rather than to yourself. Let the distance be for them.\n\nAt the end, mark the spot where you finished. You are allowed to set them down there. You are not carrying them alone.',
   'Galatians 6:2',
   'Bear one another''s burdens, and so fulfil the law of Christ.',
   'intercession', 2),

  -- ----------------------------------------------------------------- lament --
  ('For the walk you did not want to take',
   'When the route is heavy and the words have run out.',
   E'Some days the walk is not devotion, it is escape. Take it anyway.\n\nYou do not owe anyone a well-formed prayer. Say the true thing, even if the true thing is that you are tired of saying things.\n\nLament is not the absence of faith. It is faith that has stopped pretending.',
   'Psalm 13:1-2',
   'How long, LORD? Will you forget me forever? How long will you hide your face from me? How long shall I take counsel in my soul, having sorrow in my heart every day?',
   'lament', 3),

  -- -------------------------------------------------------------- stillness --
  ('Twenty minutes, no words',
   'Walk the loop without asking for anything.',
   E'Leave the phone in your pocket. Do not name a single intention.\n\nTwenty minutes is long enough to get bored, and boredom is usually where the noise finally drops.\n\nIf something surfaces, let it. You are not required to do anything with it today.',
   'Psalm 46:10',
   'Be still, and know that I am God.',
   'stillness', 1),

  ('Walk until you are tired enough to stop talking',
   'For the days your head will not go quiet.',
   E'Set out faster than you mean to finish. Let the first stretch burn off whatever you have been rehearsing since morning.\n\nWhen your breathing settles, stop arguing with whoever is not there. They are not on this walk.\n\nWhat is left when the rehearsing stops is usually the thing worth bringing.',
   'Matthew 11:28-29',
   'Come to me, all you who labour and are heavily burdened, and I will give you rest. Take my yoke upon you and learn from me, for I am gentle and lowly in heart; and you will find rest for your souls.',
   'stillness', 3),

  -- --------------------------------------------------------- scripture walk --
  ('Psalm 121, one line per kilometre',
   'A passage paced out across the route.',
   E'Take one line at the start of each kilometre and carry it until the next.\n\nDo not analyse it. Repeat it until it stops sounding like words and starts sounding like something you are walking through.\n\nIf the route is short, take fewer lines. The passage is not a target.',
   'Psalm 121:1-2',
   'I will lift up my eyes to the hills. Where does my help come from? My help comes from the LORD, who made heaven and earth.',
   'scriptureWalk', 4)

) as v(title, summary, body, scripture_ref, scripture_text, category, read_minutes)
where not exists (
  select 1 from public.devotionals d where d.title = v.title
);
