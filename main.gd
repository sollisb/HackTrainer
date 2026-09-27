extends Node2D

const NODE_R := 24.0
const COLS := 9
const ROWS := 6
const ORIGIN := Vector2(120, 155)
# Pointy-top hex-node spacing. Odd rows are offset half a column.
const HEX_X := 92.0
const HEX_Y := 76.0

enum Kind { EMPTY, DEFENSE, CORE, UTILITY }

var nodes:Array = []
var edges:Array = []
var start_id := 0
var virus_strength := 20
var virus_coherence := 80
var max_coherence := 80
var training := true
var difficulty := 1
var status := ""
var clue_flash:Dictionary = {}
var clue_timer := 0.0
var won := false
var lost := false
var rng := RandomNumberGenerator.new()

var new_btn:Button
var train_btn:CheckButton
var diff_box:OptionButton

func _ready():
    rng.randomize()
    set_process(true)
    _make_ui()
    new_hack()

func _make_ui():
    var title = Label.new()
    title.text = "HackTrainer — node hacking practice"
    title.position = Vector2(28, 20)
    title.add_theme_font_size_override("font_size", 24)
    add_child(title)

    new_btn = Button.new()
    new_btn.text = "New Hack"
    new_btn.position = Vector2(28, 62)
    new_btn.size = Vector2(120, 38)
    new_btn.pressed.connect(new_hack)
    add_child(new_btn)

    train_btn = CheckButton.new()
    train_btn.text = "Training Mode"
    train_btn.position = Vector2(170, 65)
    train_btn.button_pressed = true
    train_btn.toggled.connect(func(v): training = v; queue_redraw())
    add_child(train_btn)

    diff_box = OptionButton.new()
    diff_box.position = Vector2(350, 62)
    diff_box.size = Vector2(150, 38)
    diff_box.add_item("Easy")
    diff_box.add_item("Standard")
    diff_box.add_item("Hard")
    diff_box.selected = 1
    diff_box.item_selected.connect(func(i): difficulty = i; new_hack())
    add_child(diff_box)

    var help = Label.new()
    help.text = "Click adjacent revealed nodes. Find and destroy the System Core. Utilities repair you; defenses fight back."
    help.position = Vector2(530, 70)
    help.size = Vector2(540, 50)
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(help)

func _process(delta):
    if clue_timer > 0.0:
        clue_timer -= delta
        if clue_timer <= 0.0:
            clue_flash.clear()
            queue_redraw()

func new_hack():
    difficulty = diff_box.selected if diff_box else 1
    virus_strength = [24,20,18][difficulty]
    max_coherence = [90,80,70][difficulty]
    virus_coherence = max_coherence
    won = false
    lost = false
    status = "Start at the green node. Explore outward and hunt the System Core."
    nodes.clear(); edges.clear()
    clue_flash.clear(); clue_timer = 0.0

    # Build a regular offset hex grid: each interior node has six neighbours.
    # This makes the distance clues correspond to the topology you can see.
    for r in ROWS:
        for c in COLS:
            var id = r * COLS + c
            var x_offset = HEX_X * 0.5 if (r & 1) == 1 else 0.0
            nodes.append({
                "id":id, "p":ORIGIN + Vector2(c * HEX_X + x_offset, r * HEX_Y),
                "kind":Kind.EMPTY, "revealed":false, "visited":false,
                "dead":false, "coh":0, "str":0, "used":false
            })

    # Horizontal links plus the two downward diagonals appropriate to each row.
    # Adding only downward links avoids duplicate edges.
    for r in ROWS:
        for c in COLS:
            var a = r * COLS + c
            if c < COLS - 1:
                edges.append(Vector2i(a, a + 1))
            if r < ROWS - 1:
                edges.append(Vector2i(a, (r + 1) * COLS + c))
                if (r & 1) == 0:
                    if c > 0:
                        edges.append(Vector2i(a, (r + 1) * COLS + c - 1))
                else:
                    if c < COLS - 1:
                        edges.append(Vector2i(a, (r + 1) * COLS + c + 1))

    start_id = (ROWS / 2) * COLS
    nodes[start_id].revealed = true
    nodes[start_id].visited = true

    var candidates = range(nodes.size())
    candidates.erase(start_id)

    # Rule of 8: prefer a System Core at least eight graph steps from the start.
    var core_candidates:Array = []
    for id in candidates:
        if _shortest_distance(start_id, [id]) >= 8:
            core_candidates.append(id)
    if core_candidates.is_empty():
        core_candidates = candidates.duplicate()
    var core_id = core_candidates[rng.randi_range(0, core_candidates.size()-1)]
    nodes[core_id].kind = Kind.CORE
    nodes[core_id].coh = [35,50,65][difficulty]
    nodes[core_id].str = [10,14,18][difficulty]

    # Rule of Six: a complete six-neighbour node is safe from a defensive
    # subsystem unless that node is adjacent to the System Core.
    var defense_candidates:Array = []
    for id in candidates:
        if id == core_id:
            continue
        var complete = _neighbors(id).size() == 6
        var adjacent_to_core = core_id in _neighbors(id)
        if not complete or adjacent_to_core:
            defense_candidates.append(id)

    var defenses = [7,10,13][difficulty]
    for i in defenses:
        var id = _random_empty(defense_candidates)
        nodes[id].kind = Kind.DEFENSE
        nodes[id].coh = rng.randi_range(22 + difficulty*7, 38 + difficulty*12)
        nodes[id].str = rng.randi_range(7 + difficulty*2, 12 + difficulty*4)
    for i in 5:
        var id = _random_empty(candidates)
        nodes[id].kind = Kind.UTILITY
    _reveal_neighbors(start_id)
    queue_redraw()

func _random_empty(candidates:Array) -> int:
    while true:
        var id = candidates[rng.randi_range(0,candidates.size()-1)]
        if nodes[id].kind == Kind.EMPTY:
            return id
    return -1

func _neighbors(id:int) -> Array:
    var out=[]
    for e in edges:
        if e.x == id: out.append(e.y)
        elif e.y == id: out.append(e.x)
    return out

func _reveal_neighbors(id:int):
    for n in _neighbors(id): nodes[n].revealed = true

func _can_click(id:int) -> bool:
    if won or lost or not nodes[id].revealed or nodes[id].dead: return false
    if nodes[id].visited and nodes[id].kind == Kind.EMPTY: return false
    for n in _neighbors(id):
        if nodes[n].visited and (nodes[n].kind == Kind.EMPTY or nodes[n].dead or nodes[n].kind == Kind.UTILITY): return true
    return id == start_id

func _input(event):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for n in nodes:
            if event.position.distance_to(n.p) <= NODE_R and _can_click(n.id):
                _activate(n.id); return

func _activate(id:int):
    var n = nodes[id]

    # Discovering a hostile subsystem is free. The first click only exposes it;
    # a later click attacks it. This keeps exploration separate from combat.
    if not n.visited:
        n.visited = true
        match n.kind:
            Kind.EMPTY:
                var clue = _distance_clue(id)
                clue_flash[id] = clue
                clue_timer = 2.2
                status = "Clear node — distance clue %d. Smaller numbers lead toward something useful." % clue
                _reveal_neighbors(id)
            Kind.UTILITY:
                var heal = [28,24,20][difficulty]
                virus_coherence = min(max_coherence, virus_coherence + heal)
                n.used = true
                n.dead = true
                status = "Utility found: +%d Virus Coherence." % heal
                _reveal_neighbors(id)
            Kind.DEFENSE:
                status = "Defensive subsystem discovered. Click it again to attack."
            Kind.CORE:
                status = "SYSTEM CORE discovered. Click it again to attack."
        queue_redraw()
        return

    # A revealed hostile subsystem is attacked only by an explicit later click.
    if n.kind == Kind.DEFENSE or n.kind == Kind.CORE:
        _combat(id)
        queue_redraw()

func _distance_clue(from_id:int) -> int:
    # EVE-style clue: graph distance to nearest Core, Utility or Data Cache.
    # Defensive subsystems deliberately do not count.
    var targets:Array = []
    for n in nodes:
        if n.kind == Kind.CORE or n.kind == Kind.UTILITY:
            targets.append(n.id)
    var d = _shortest_distance(from_id, targets)
    return min(5, d) if d >= 0 else 5

func _shortest_distance(from_id:int, targets:Array) -> int:
    if from_id in targets:
        return 0
    var q:Array = [from_id]
    var dist:Dictionary = {from_id: 0}
    while not q.is_empty():
        var cur:int = q.pop_front()
        for nxt in _neighbors(cur):
            if dist.has(nxt):
                continue
            var nd:int = int(dist[cur]) + 1
            if nxt in targets:
                return nd
            dist[nxt] = nd
            q.append(nxt)
    return -1

func _combat(id:int):
    var n = nodes[id]
    n.coh -= virus_strength
    if n.coh <= 0:
        n.dead = true
        _reveal_neighbors(id)
        if n.kind == Kind.CORE:
            won = true; status = "SYSTEM CORE DESTROYED — hack successful!"
        else:
            status = "Defense destroyed. Path opened."
    else:
        virus_coherence -= n.str
        status = "You hit for %d. Defense hits back for %d." % [virus_strength,n.str]
        if virus_coherence <= 0:
            virus_coherence = 0; lost = true; status = "VIRUS DESTROYED — hack failed."

func _draw():
    for e in edges:
        if nodes[e.x].revealed and nodes[e.y].revealed:
            draw_line(nodes[e.x].p, nodes[e.y].p, Color(0.32,0.38,0.44), 2.0)
    for n in nodes:
        if not n.revealed: continue
        var col = Color(0.25,0.30,0.35)
        if n.id == start_id: col = Color(0.20,0.65,0.35)
        if n.visited: col = Color(0.28,0.48,0.62)
        if n.kind == Kind.DEFENSE and n.visited: col = Color(0.78,0.30,0.24)
        if n.kind == Kind.CORE and n.visited: col = Color(0.85,0.55,0.16)
        if n.kind == Kind.UTILITY and n.visited: col = Color(0.38,0.68,0.72)
        if n.dead: col = Color(0.20,0.22,0.24)
        draw_circle(n.p, NODE_R, col)
        draw_circle(n.p, NODE_R, Color(0.75,0.80,0.84), false, 2.0)
        var txt = "?"
        if clue_flash.has(n.id):
            txt = str(clue_flash[n.id])
        elif n.visited:
            match n.kind:
                Kind.EMPTY: txt = "•"
                Kind.DEFENSE: txt = "D" if not n.dead else "×"
                Kind.CORE: txt = "CORE" if not n.dead else "✓"
                Kind.UTILITY: txt = "+" if not n.used else "✓"
        draw_string(ThemeDB.fallback_font, n.p + Vector2(-16,5), txt, HORIZONTAL_ALIGNMENT_CENTER, 32, 13, Color.WHITE)
        if n.visited and (n.kind == Kind.DEFENSE or n.kind == Kind.CORE) and not n.dead:
            draw_string(ThemeDB.fallback_font, n.p + Vector2(-22,39), "%d HP / %d DMG" % [max(0,n.coh),n.str], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9,0.9,0.9))

    draw_string(ThemeDB.fallback_font, Vector2(30,665), "Virus: %d/%d coherence     Strength: %d" % [virus_coherence,max_coherence,virus_strength], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.88,0.9,0.92))
    draw_string(ThemeDB.fallback_font, Vector2(430,665), status, HORIZONTAL_ALIGNMENT_LEFT, 630, 16, Color(0.88,0.9,0.92))
    if training and not won and not lost:
        var hint = _training_hint()
        draw_string(ThemeDB.fallback_font, Vector2(30,700), "Trainer: " + hint, HORIZONTAL_ALIGNMENT_LEFT, 1040, 14, Color(0.65,0.78,0.88))

func _training_hint() -> String:
    var options=[]
    for n in nodes:
        if _can_click(n.id):
            options.append(n)

    # Teach the useful consequence without exposing hidden contents.
    for n in options:
        if not n.visited and _neighbors(n.id).size() == 6:
            return "Rule of Six: a node with all 6 neighbours is normally safe from defenses. Exception: if it borders the Core."

    var empties = options.filter(func(x): return not x.visited or x.kind == Kind.EMPTY)
    if empties.size() > 0:
        return "Follow decreasing distance clues and prefer complete 6-neighbour nodes when available."
    return "If a defense blocks the only route, attack it; watch Coherence before committing."
