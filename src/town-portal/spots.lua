-- The game's teleport portals, in the order of the bits of the hero's portal word (gear.world.portals) and of the lines of the game's own list
-- ("Transferportal"): 13 of them. `x`, `y` are where the game puts the hero (read by choosing each line of the game's list with every bit set).
-- Names in the languages of the game; the game's own list takes them from its texts, which Gear cannot read, so they are written here.
return {
    {bit = 0,  x = 180182, y = 131990, name = {en = 'Bellevue', de = 'Schönblick'}},
    {bit = 1,  x = 141811, y = 164082, name = {en = 'Porto Vallum', de = 'Porto Vallum'}},
    {bit = 2,  x = 72099,  y = 120184, name = {en = 'Icecreek Pass', de = 'Eisbachpass'}},
    {bit = 3,  x = 128064, y = 223275, name = {en = 'Fields of Urkuk', de = 'Ebene von Urkuk'}},
    {bit = 4,  x = 74783,  y = 151856, name = {en = 'Timberton', de = 'Biberingen'}},
    {bit = 5,  x = 99844,  y = 187641, name = {en = 'Mascarell', de = 'Mascarell'}},
    {bit = 6,  x = 187856, y = 192686, name = {en = 'Khorad-Nur', de = 'Khorad-Nur'}},
    {bit = 7,  x = 131775, y = 107894, name = {en = 'Braverock Castle', de = 'Burg Hohenmut'}},
    {bit = 8,  x = 74890,  y = 80954,  name = {en = 'Monastery of the Seraphim', de = 'Klosterfeste der Seraphim'}},
    {bit = 9,  x = 168107, y = 119164, name = {en = 'Hedgenton', de = 'Heckenheim'}},
    {bit = 10, x = 176640, y = 74997,  name = {en = 'Valley of Zhurag-Nar', de = 'Tal von Zhurag-Nar'}},
    {bit = 11, x = 218016, y = 134620, name = {en = 'Mystdale Castle', de = 'Burg Sternental'}},
    {bit = 12, x = 248230, y = 133600, name = {en = 'Shaddar-Nur', de = 'Shaddar-Nur'}},
}
