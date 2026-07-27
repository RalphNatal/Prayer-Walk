-- ===========================================================================
-- SEED — run once, by hand, by the maintainer. NOT a migration.
-- ===========================================================================
--
-- This file is deliberately not in `supabase/migrations/`. It is content, not
-- schema: re-running a migration must be safe on every project, whereas this
-- is a starting library that an admin is expected to edit, extend and prune
-- from the admin screens afterwards. Paste it into the Supabase SQL editor
-- after `20260727020000_scripture_prompts.sql` has been applied.
--
-- It is idempotent — a prompt with the same reference and body is skipped —
-- so running it twice does not duplicate the library.
--
-- LICENSING
-- ---------
-- Every scripture row below is the World English Bible, British Edition
-- (WEBBE): public domain, no licence fee, no attribution obligation. The
-- British edition is used rather than the base WEB because it renders the
-- divine name as "the LORD" rather than "Yahweh", which is the form Catholic
-- usage expects. Re-pull from https://ebible.org/webbe/ if byte-exact text
-- matters to you.
--
-- Rows with kind = 'prayer' carry no translation: they are either ancient
-- formulas long in the public domain (the Jesus Prayer, Anima Christi) or
-- written for this app.
--
-- Nothing here is drawn from the NIV, ESV, NLT, NASB or CSB. Those are
-- copyrighted and may not be redistributed in an app without a paid licence;
-- do not paste them into this table.
--
-- The same set ships as `assets/scripture/prompts.json`, which is the offline
-- floor when a device has never synced. Keep the two in step if you edit one.

insert into public.scripture_prompts
  (reference, body, translation, kind, category, sort_order)
select v.reference, v.body, v.translation, v.kind, v.category, v.sort_order
from (values
  -- ---------------------------------------------------------- morning light --
  ('Psalm 5:3',
   'LORD, in the morning you will hear my voice. In the morning I will lay my requests before you, and will watch expectantly.',
   'WEBBE', 'scripture', 'morningLight', 10),
  ('Lamentations 3:22-23',
   'It is because of the LORD''s loving kindnesses that we are not consumed, because his compassion doesn''t fail. They are new every morning. Great is your faithfulness.',
   'WEBBE', 'scripture', 'morningLight', 20),
  ('Psalm 143:8',
   'Cause me to hear your loving kindness in the morning, for I trust in you. Cause me to know the way in which I should walk, for I lift up my soul to you.',
   'WEBBE', 'scripture', 'morningLight', 30),
  ('Mark 1:35',
   'Early in the morning, while it was still dark, he rose up and went out, and departed into a deserted place, and prayed there.',
   'WEBBE', 'scripture', 'morningLight', 40),
  ('Psalm 118:24',
   'This is the day that the LORD has made. We will rejoice and be glad in it.',
   'WEBBE', 'scripture', 'morningLight', 50),
  ('Isaiah 40:31',
   'But those who wait for the LORD will renew their strength. They will mount up with wings like eagles. They will run, and not be weary. They will walk, and not faint.',
   'WEBBE', 'scripture', 'morningLight', 60),
  ('Before the first mile',
   'Lord, the day is not mine to command. Walk it with me, and let me notice what you have already put in it.',
   '', 'prayer', 'morningLight', 70),

  -- -------------------------------------------------------------- gratitude --
  ('Psalm 100:4',
   'Enter into his gates with thanksgiving, and into his courts with praise. Give thanks to him, and bless his name.',
   'WEBBE', 'scripture', 'gratitude', 110),
  ('1 Thessalonians 5:16-18',
   'Always rejoice. Pray without ceasing. In everything give thanks, for this is the will of God in Christ Jesus toward you.',
   'WEBBE', 'scripture', 'gratitude', 120),
  ('Psalm 107:1',
   'Give thanks to the LORD, for he is good, for his loving kindness endures forever.',
   'WEBBE', 'scripture', 'gratitude', 130),
  ('James 1:17',
   'Every good gift and every perfect gift is from above, coming down from the Father of lights, with whom can be no variation, nor turning shadow.',
   'WEBBE', 'scripture', 'gratitude', 140),
  ('Psalm 103:2',
   'Praise the LORD, my soul, and don''t forget all his benefits.',
   'WEBBE', 'scripture', 'gratitude', 150),
  ('Colossians 3:15',
   'And let the peace of God rule in your hearts, to which also you were called in one body, and be thankful.',
   'WEBBE', 'scripture', 'gratitude', 160),
  ('On the way home',
   'For the road under me, the breath in me, and the people waiting at the end of it — thank you.',
   '', 'prayer', 'gratitude', 170),

  -- ----------------------------------------------------------- intercession --
  ('Philippians 4:6',
   'In nothing be anxious, but in everything, by prayer and petition with thanksgiving, let your requests be made known to God.',
   'WEBBE', 'scripture', 'intercession', 210),
  ('Galatians 6:2',
   'Bear one another''s burdens, and so fulfil the law of Christ.',
   'WEBBE', 'scripture', 'intercession', 220),
  ('James 5:16',
   'Confess your sins to one another and pray for one another, that you may be healed. The insistent prayer of a righteous person is powerfully effective.',
   'WEBBE', 'scripture', 'intercession', 230),
  ('1 Timothy 2:1',
   'I exhort therefore, first of all, that petitions, prayers, intercessions, and givings of thanks be made for all people.',
   'WEBBE', 'scripture', 'intercession', 240),
  ('Matthew 7:7',
   'Ask, and it will be given you. Seek, and you will find. Knock, and it will be opened for you.',
   'WEBBE', 'scripture', 'intercession', 250),
  ('Romans 12:12',
   'Rejoicing in hope; enduring in troubles; continuing steadfastly in prayer.',
   'WEBBE', 'scripture', 'intercession', 260),
  ('Ephesians 6:18',
   'With all prayer and requests, praying at all times in the Spirit, and being watchful to this end in all perseverance and requests for all the saints.',
   'WEBBE', 'scripture', 'intercession', 270),
  ('Carrying someone',
   'Hold the one I am carrying. I cannot fix it, and I am not asked to. I can only keep walking and keep asking.',
   '', 'prayer', 'intercession', 280),

  -- ----------------------------------------------------------------- lament --
  ('Psalm 34:18',
   'The LORD is near to those who have a broken heart, and saves those who have a crushed spirit.',
   'WEBBE', 'scripture', 'lament', 310),
  ('Psalm 42:11',
   'Why are you in despair, my soul? Why are you disturbed within me? Hope in God! For I shall still praise him.',
   'WEBBE', 'scripture', 'lament', 320),
  ('Matthew 11:28',
   'Come to me, all you who labour and are heavily burdened, and I will give you rest.',
   'WEBBE', 'scripture', 'lament', 330),
  ('Psalm 130:1-2',
   'Out of the depths I have cried to you, LORD. Lord, hear my voice. Let your ears be attentive to the voice of my petitions.',
   'WEBBE', 'scripture', 'lament', 340),
  ('Psalm 23:4',
   'Even though I walk through the valley of the shadow of death, I will fear no evil, for you are with me.',
   'WEBBE', 'scripture', 'lament', 350),
  ('2 Corinthians 12:9',
   'He has said to me, "My grace is sufficient for you, for my power is made perfect in weakness."',
   'WEBBE', 'scripture', 'lament', 360),
  ('Psalm 56:8',
   'You count my wanderings. You put my tears into your container. Aren''t they in your book?',
   'WEBBE', 'scripture', 'lament', 370),
  ('The Jesus Prayer',
   'Lord Jesus Christ, Son of God, have mercy on me, a sinner.',
   '', 'prayer', 'lament', 380),

  -- -------------------------------------------------------------- stillness --
  ('Psalm 46:10',
   'Be still, and know that I am God.',
   'WEBBE', 'scripture', 'stillness', 410),
  ('1 Kings 19:12',
   'After the earthquake a fire passed; but the LORD was not in the fire. After the fire, there was a still small voice.',
   'WEBBE', 'scripture', 'stillness', 420),
  ('Psalm 62:1',
   'My soul rests in God alone. My salvation is from him.',
   'WEBBE', 'scripture', 'stillness', 430),
  ('Isaiah 30:15',
   'In returning and rest you will be saved. In quietness and in confidence will be your strength.',
   'WEBBE', 'scripture', 'stillness', 440),
  ('Psalm 131:2',
   'Surely I have stilled and quieted my soul, like a weaned child with his mother, like a weaned child is my soul within me.',
   'WEBBE', 'scripture', 'stillness', 450),
  ('Habakkuk 2:20',
   'But the LORD is in his holy temple. Let all the earth be silent before him.',
   'WEBBE', 'scripture', 'stillness', 460),
  ('Fewer words',
   'I have nothing to say that you have not already heard. Let the walking be the prayer.',
   '', 'prayer', 'stillness', 470),

  -- --------------------------------------------------------- scripture walk --
  ('Psalm 121:1-2',
   'I will lift up my eyes to the hills. Where does my help come from? My help comes from the LORD, who made heaven and earth.',
   'WEBBE', 'scripture', 'scriptureWalk', 510),
  ('Psalm 119:105',
   'Your word is a lamp to my feet, and a light for my path.',
   'WEBBE', 'scripture', 'scriptureWalk', 520),
  ('Micah 6:8',
   'He has shown you, O man, what is good. What does the LORD require of you, but to act justly, to love mercy, and to walk humbly with your God?',
   'WEBBE', 'scripture', 'scriptureWalk', 530),
  ('Luke 24:32',
   'Weren''t our hearts burning within us while he spoke to us along the way, and while he opened the Scriptures to us?',
   'WEBBE', 'scripture', 'scriptureWalk', 540),
  ('Proverbs 3:6',
   'In all your ways acknowledge him, and he will make your paths straight.',
   'WEBBE', 'scripture', 'scriptureWalk', 550),
  ('Isaiah 43:2',
   'When you pass through the waters, I will be with you, and through the rivers, they will not overflow you.',
   'WEBBE', 'scripture', 'scriptureWalk', 560),
  ('Psalm 16:11',
   'You will show me the path of life. In your presence is fullness of joy. In your right hand there are pleasures forever more.',
   'WEBBE', 'scripture', 'scriptureWalk', 570),
  ('Deuteronomy 31:8',
   'The LORD himself is who goes before you. He will be with you. He will not fail you nor forsake you. Don''t be afraid, neither be dismayed.',
   'WEBBE', 'scripture', 'scriptureWalk', 580),
  ('Genesis 5:24',
   'Enoch walked with God, and he was not found, for God took him.',
   'WEBBE', 'scripture', 'scriptureWalk', 590),
  ('Anima Christi',
   'Soul of Christ, sanctify me. Body of Christ, save me. Within your wounds hide me.',
   '', 'prayer', 'scriptureWalk', 600)
) as v(reference, body, translation, kind, category, sort_order)
where not exists (
  select 1
  from public.scripture_prompts p
  where p.reference = v.reference and p.body = v.body
);
