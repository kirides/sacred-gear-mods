"""Draws the schematic preview pictures of the mods that have no real screenshot yet (docs/images/<id>.svg).
Run: python tools/illustrations/make.py   -- they are illustrations with example values, not screenshots.
Replace one with a real screenshot (docs/images/<id>.jpg) and point the README table at it."""
import os, html

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'docs', 'images')
W, H = 480, 270
GOLD, TEXT, DIM, GREEN, BLUE, YEL, RED = '#d8b45a', '#efe6d2', '#9a8f7c', '#7fc47f', '#6f9bff', '#f0d060', '#e07060'


def esc(t):
    return html.escape(t, quote=False)


def panel(x, y, w, h, title=None, rows=(), size=13, gap=20):
    s = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" fill="#1a1410" fill-opacity="0.92" stroke="{GOLD}" stroke-width="1.5"/>'
    ty = y
    if title:
        s += f'<text x="{x+10}" y="{y+20}" font-size="14" font-weight="bold" fill="{GOLD}">{esc(title)}</text>'
        s += f'<line x1="{x+8}" y1="{y+28}" x2="{x+w-8}" y2="{y+28}" stroke="{GOLD}" stroke-opacity="0.4"/>'
        ty = y + 34
    for i, r in enumerate(rows):
        t, c = (r, TEXT) if isinstance(r, str) else r
        s += f'<text x="{x+10}" y="{ty+16+i*gap}" font-size="{size}" fill="{c}" xml:space="preserve">{esc(t)}</text>'
    return s


def toast(text, y=14, w=300):
    x = (W - w) // 2
    return (f'<rect x="{x}" y="{y}" width="{w}" height="30" rx="15" fill="#1a1410" fill-opacity="0.92" stroke="{GOLD}"/>'
            f'<text x="{W//2}" y="{y+20}" font-size="13" fill="{TEXT}" text-anchor="middle">{esc(text)}</text>')


def button(x, y, w, label, on=False):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="24" rx="3" fill="{"#3a2c14" if on else "#2a2018"}" stroke="{GOLD}"/>'
            f'<text x="{x+w/2}" y="{y+16}" font-size="12" fill="{TEXT}" text-anchor="middle">{esc(label)}</text>')


def frame(x, y, w, h, label):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#1a1410" fill-opacity="0.9" stroke="{GREEN}" stroke-width="2" stroke-dasharray="6 4"/>'
            f'<text x="{x+w/2}" y="{y+h/2+4}" font-size="13" fill="{TEXT}" text-anchor="middle">{esc(label)}</text>')


def box(x, y, w, h, label):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="#1a1410" stroke="{GOLD}"/>'
            f'<text x="{x+w/2}" y="{y+h/2+4}" font-size="13" fill="{TEXT}" text-anchor="middle">{esc(label)}</text>')


def line(text, x, y, color, anchor='start', opacity=1):
    return f'<text x="{x}" y="{y}" font-size="13" fill="{color}" fill-opacity="{opacity}" text-anchor="{anchor}">{esc(text)}</text>'


M = {}
M['achievements'] = (toast('Achievement unlocked: Monster Hunter', 12, 320) + toast('Daily login: day 5, +250 gold', 48, 290)
                     + panel(120, 96, 240, 154, 'Achievements', [('Monster Hunter: done', GREEN), 'Deep Delver: 3 / 5', 'Gold Hoarder: 4200 / 10000', ('Login streak: 5 days', YEL)]))
M['auction-house'] = (panel(30, 24, 420, 222, 'Auction house', [('Item / seller / price', DIM), 'Ancient Sword of Fire - Ria - 12 400', 'Helm of the Warden - Kell - 3 150', 'Ring of Quickness - Tomm - 870'])
                      + button(44, 206, 90, 'Buy', True) + button(144, 206, 90, 'Sell'))
M['bounty'] = (panel(60, 30, 360, 130, 'Bounty board', ['Hunt 20 wolves: 12 / 20, 1 h 20 min left', 'Slay the orc chief: 0 / 1, 3 h 05 min left', ('Reward: 500 gold', YEL)])
               + panel(300, 180, 170, 70, None, ['Wolves 12 / 20', 'Orc chief 0 / 1']))
M['buildsharer'] = (panel(40, 20, 400, 230, 'Build sharer', [('Title / class / level', DIM), 'Fire storm - Battle Mage - 41', 'Tank for two - Gladiator - 37', 'Bow and traps - Wood Elf - 44'])
                    + button(54, 206, 110, 'Publish mine', True) + button(174, 206, 80, 'Open'))
M['damagemeter'] = panel(150, 70, 180, 100, None, ['Seraphina   1 240 DPS', 'Brom   860 DPS', 'Mira   455 DPS'], 14, 26)
M['drop-tuning'] = panel(50, 20, 380, 230, 'Drop tuning', ['Drop chance: x1.5', 'Rare items: +20 %', 'Unique and set items: +10 %', ('Fair random generator: on', GREEN), ('Every setting starts "as the game has it"', DIM)], 13, 30)
M['layout'] = (frame(30, 30, 190, 110, 'Backpack') + frame(260, 40, 190, 80, 'Damage meter') + frame(150, 160, 180, 70, 'Loot log')
               + button(8, 8, 100, 'Edit layout', True))
M['lootlog'] = panel(50, 20, 380, 230, 'Loot log', [('Quality v   Category v   Kind v', DIM), ('Dropped: Ring of Quickness', BLUE), ('Picked up: Helm of the Warden', YEL), ('Dropped: Sword of Dawn (set)', GREEN), ('Picked up: Amulet of Stone', BLUE), ], 13, 28)
M['questhelper'] = panel(50, 20, 380, 230, 'Quest helper', [('In your backpack', DIM), 'Old Key (quest item)', ('Quest records', DIM), 'The Lost Caravan: step 2', ('Hint: look near the east bridge', DIM)], 13, 30)
M['realms'] = (panel(60, 40, 360, 150, 'Mods > Realm', [('Online play server (Closed / Open Internet)', DIM)])
               + f'<rect x="74" y="96" width="250" height="26" rx="3" fill="#2a2018" stroke="{GOLD}"/>' + line('Private realm (realm.example.com)', 86, 114, TEXT) + line('v', 308, 114, GOLD) + line('Host: realm.example.com:7066', 74, 150, DIM))
M['serverfeed'] = (line('Ria found Ancient Sword of Fire!', 468, 190, YEL, 'end') + line('Kell has fallen in the Ice Caves', 468, 212, RED, 'end')
                   + line('Tomm found Ring of Quickness!', 468, 234, YEL, 'end'))
M['sessiontracker'] = panel(120, 40, 240, 170, 'This session', ['Played: 1 h 12 min', 'Kills: 341 (284 per hour)', ('Gold: +18 400 (15.3k per hour)', YEL), ('Experience: +96 000', GREEN)], 13, 28)
M['twi_sacred'] = toast("Viewer42's Wolf appears nearby!", 20, 320) + toast('Gold +500 from Viewer7', 60, 260) + toast('Teleport!', 100, 150)
M['twitch_integration'] = (box(20, 95, 120, 60, 'Twitch connector') + box(180, 95, 120, 60, 'Twitch base mod') + box(340, 95, 120, 60, 'Action mods')
                           + f'<path d="M140 125 h40 M300 125 h40" stroke="{GOLD}" stroke-width="2"/>'
                           + line('rewards, bits and chat commands become actions in the game', 240, 200, DIM, 'middle'))

for k, body in M.items():
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="Segoe UI, Arial, sans-serif">'
           f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b3226"/><stop offset="1" stop-color="#1c1710"/></linearGradient></defs>'
           f'<rect width="{W}" height="{H}" fill="url(#g)"/>{body}'
           f'<text x="{W-6}" y="{H-5}" font-size="9" fill="{DIM}" text-anchor="end">illustration with example values</text></svg>')
    with open(os.path.join(OUT, k + '.svg'), 'w', encoding='utf-8') as f:
        f.write(svg)
print(len(M), 'pictures')
