-- copyright to Tymek29216 (altf4developer). All rights reversed.
local Players, RS, TS = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("TweenService")
local AssetService, TCS = game:GetService("AssetService"), game:GetService("TextChatService")
local evCue, evRole, evAction, started = RS:WaitForChild("DarkRoomCue"), RS:WaitForChild("DarkRoomRole"), RS:WaitForChild("DarkRoomAction"), RS:WaitForChild("MatchStarted")
pcall(function() TCS.ChatWindowConfiguration.Enabled = false; TCS.ChatInputBarConfiguration.Enabled = false end)
pcall(function() game:GetService("VoiceChatService").EnableDefaultVoice = false end)

local T = {elim = 20, sheriff = 15, doctor = 15, vote = 15, confirm = 10, ending = 10}
local V = {
	sleep = {96915631738839, "I'm choosing the eliminator. City, go to sleep."}, hmm = {70926844811834, "hmm..."}, them = {94021546869118, "ok. them."},
	sheriffPick = {108187704559090, "Alright, now choosing a sheriff. hm, him."}, doctorPick = {106048393956301, "Choosing a doctor! him."},
	citySleeps = {100129205398701, "City sleeps."}, elimWake = {112609158935546, "Eliminators, wake up!"}, chooseKill = {122969577624361, "Choose the person to eliminate!"},
	doctorWake = {79735536422055, "Doctor, wake up!"}, sheriffWake = {78710991970253, "Sheriff, wake up!"}, chooseCheck = {129222703943132, "Choose the person to check!"},
	chooseHeal = {93018199059042, "Choose the person to heal!"}, cityWakes = {74026990247645, "City wakes up!"}, goSleep = {129985198079700, "Go to sleep now."},
	timeToVote = {97713998183246, "Time to vote."}, chooseVote = {134951046054350, "Choose the person you think is the eliminator, or skip!"},
	outClear = {97572593045599, "This person was voted out, and he was clear!"}, outElim = {85508102212870, "This person was voted out, and he was an eliminator!"},
	outDoctor = {115441922652351, "This person was voted out, and he was a doctor!"}, outSheriff = {89608610265740, "This person was voted out, and he was a sheriff!"},
}
local room = workspace:WaitForChild("DarkRoom")
local hostModel, sounds, hostDesc = nil, {}, nil
local vf = Instance.new("Folder"); vf.Name = "HostVoices"; vf.Parent = room
for k, v in pairs(V) do
	local so = Instance.new("Sound"); so.Name = k; so.SoundId = "rbxassetid://" .. v[1]; so.Volume = 1.2; so.RollOffMinDistance = 14; so.RollOffMaxDistance = 140; so.Parent = vf; sounds[k] = so
end
local function len(k) local so = sounds[k]; if so.IsLoaded and so.TimeLength > 0 then return so.TimeLength end return #V[k][2] * 0.06 + 0.6 end

task.spawn(function()
	local desc = Instance.new("HumanoidDescription")
	pcall(function()
		for id = 1, 12 do
			local ok, d = pcall(AssetService.GetBundleDetailsAsync, AssetService, id)
			if ok and d and d.Name == "Woman" then
				for _, it in ipairs(d.Items) do
					if it.Type == "Asset" then
						local n = it.Name:lower()
						if n:find("torso") then desc.Torso = it.Id elseif n:find("left arm") then desc.LeftArm = it.Id elseif n:find("right arm") then desc.RightArm = it.Id
						elseif n:find("left leg") then desc.LeftLeg = it.Id elseif n:find("right leg") then desc.RightLeg = it.Id elseif n:find("head") then desc.Head = it.Id end
					end
				end
				break
			end
		end
	end)
	desc.BodyTypeScale = 0.35; desc.WidthScale = 0.9
	local skin, dress = Color3.fromRGB(226, 182, 150), Color3.fromRGB(120, 24, 40)
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor, desc.TorsoColor, desc.LeftLegColor, desc.RightLegColor = skin, skin, skin, dress, dress, dress
	hostDesc = desc
end)

local bulb = room:FindFirstChild("TheLight"); local spot = bulb and bulb:FindFirstChildOfClass("SpotLight")
local WARM, COLD = Color3.fromRGB(255, 240, 200), Color3.fromRGB(150, 170, 255)
local function mood(night)
	if not spot then return end
	TS:Create(spot, TweenInfo.new(2.2, Enum.EasingStyle.Sine), {Brightness = night and 0.9 or 4, Color = night and COLD or WARM}):Play()
	TS:Create(bulb, TweenInfo.new(2.2, Enum.EasingStyle.Sine), {Color = night and COLD or WARM}):Play()
end

local P, byId, sel = {}, {}, nil
local roundEnded = true
local function cue(list, kind, data) for _, pt in ipairs(list or P) do if pt.player and pt.player.Parent then evCue:FireClient(pt.player, kind, data) end end end
local function say(k, list) local d = len(k); cue(list, "say", {text = V[k][2], dur = d}); sounds[k].TimePosition = 0; sounds[k]:Play(); return d end
local function announce(text, list) cue(list, "announce", {text = text}) end
local function alive(f) local t = {} for _, pt in ipairs(P) do if pt.alive and (not f or f(pt)) then table.insert(t, pt) end end return t end
local function ptOf(plr) for _, pt in ipairs(P) do if pt.player == plr then return pt end end end
local function pick(list) return #list > 0 and list[math.random(#list)] or nil end
local function seated(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid"); local st = hum and hum.SeatPart
	return st and st:IsA("Seat") and st:IsDescendantOf(room)
end
local function buildParticipants()
	P, byId = {}, {}
	local id = 0
	local function add(name, model, plr) id += 1; local pt = {id = id, name = name, model = model, player = plr, alive = true}; table.insert(P, pt); byId[id] = pt; model:SetAttribute("PID", id) end
	for _, plr in ipairs(Players:GetPlayers()) do if plr.Character and seated(plr.Character) then add(plr.DisplayName, plr.Character, plr) end end
	local npcs = room:FindFirstChild("NPCs"); if npcs then for _, m in ipairs(npcs:GetChildren()) do add(m.Name, m, nil) end end
end
local function saveLook(pt)
	pt.saved = {}
	for _, p in ipairs(pt.model:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(pt.saved, {p = p, c = p.Color, t = p.Transparency})
		elseif p:IsA("Motor6D") and p.Name == "Neck" then pt.neck, pt.neckC0 = p, p.C0 end
	end
end
local function markDead(pt)
	pt.alive = false
	for _, e in ipairs(pt.saved or {}) do if e.p.Parent and e.p.Name ~= "HumanoidRootPart" then e.p.Color = Color3.fromRGB(38, 38, 42); e.p.Transparency = math.max(e.t, 0.35) end end
	if pt.neck then pt.neck.C0 = pt.neckC0 * CFrame.Angles(-math.rad(50), 0, 0) end
	if pt.player then evCue:FireClient(pt.player, "eliminated") end
end
local function restoreAll()
	for _, pt in ipairs(P) do
		pt.alive = true
		for _, e in ipairs(pt.saved or {}) do if e.p.Parent then e.p.Color = e.c; e.p.Transparency = e.t end end
		if pt.neck then pt.neck.C0 = pt.neckC0 end
	end
end
local function winner()
	local e, o = 0, 0
	for _, pt in ipairs(P) do if pt.alive then if pt.role == "Eliminator" then e += 1 else o += 1 end end end
	if e == 0 then return "City" elseif e >= o then return "Eliminators" end
end

local function buildHost()
	if hostModel and hostModel.Parent then return end
	local t0 = os.clock(); while not hostDesc and os.clock() - t0 < 5 do task.wait(0.1) end
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, hostDesc or Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	if not ok or not model then return end
	model.Name = "Host"; model:SetAttribute("Host", true)
	local hum = model:FindFirstChildOfClass("Humanoid"); hum.DisplayName = "Nova"; hum.HealthDisplayDistance = 0
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then table.insert(parts, {p = p, t = p.Transparency}); p.Transparency = 1 end end
	model.Parent = room; model:PivotTo(CFrame.new(0, 3.2, 0) * CFrame.Angles(0, math.rad(45), 0))
	task.wait(0.1)
	local root = model:FindFirstChild("HumanoidRootPart"); if root then root.Anchored = true end
	pcall(function() local a = Instance.new("Animation"); a.AnimationId = "rbxassetid://507766666"; local tr = (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)):LoadAnimation(a); tr.Looped = true; tr:Play() end)
	local head = model:FindFirstChild("Head"); if head then for _, so in pairs(sounds) do so.Parent = head end end
	hostModel = model
	for i = 1, 8 do for _, e in ipairs(parts) do e.p.Transparency = 1 - (1 - e.t) * (i / 8) end task.wait(0.05) end
end
local function faceToward(model)
	if not hostModel then return end
	local from = hostModel:GetPivot()
	local goal = model and CFrame.lookAt(from.Position, Vector3.new(model:GetPivot().Position.X, from.Position.Y, model:GetPivot().Position.Z)) or CFrame.new(from.Position) * CFrame.Angles(0, math.rad(45), 0)
	task.spawn(function() for i = 1, 20 do local a = i / 20; a = a * a * (3 - 2 * a); hostModel:PivotTo(from:Lerp(goal, a)); task.wait(0.025) end end)
end

-- NPC brains
local susp, known, lastVotes = {}, {}, {}
local function S(npc, tid) return (susp[npc.id] or {})[tid] or 0 end
local function addS(npc, tid, v) susp[npc.id] = susp[npc.id] or {}; susp[npc.id][tid] = (susp[npc.id][tid] or 0) + v end
local function npcsAlive() return alive(function(p) return not p.player end) end
local function tallyOf(choices) local c = {} for _, v in pairs(choices) do if type(v) == "number" then c[v] = (c[v] or 0) + 1 end end return c end
local function npcVote(npc, my)
	local others = alive(function(x) return x.id ~= npc.id end)
	local counts = tallyOf(my.choices)
	if npc.role == "Eliminator" then
		local best, bn
		for id, n in pairs(counts) do if byId[id].role ~= "Eliminator" and (not bn or n > bn) then best, bn = id, n end end
		if best and math.random() < 0.7 then return byId[best] end
		if math.random() < 0.2 then return "skip" end
		return pick(alive(function(x) return x.role ~= "Eliminator" end))
	end
	local mem = known[npc.id] or {}
	for tid, role in pairs(mem) do if role == "Eliminator" and byId[tid].alive then return byId[tid] end end
	local top, topS = nil, 0.99
	for _, c in ipairs(others) do
		local sc = S(npc, c.id) + (math.random() - 0.5) * 0.4
		if mem[c.id] then sc = -10 end
		if sc > topS then top, topS = c, sc end
	end
	if top and math.random() < 0.8 then return top end
	local best, bn
	for id, n in pairs(counts) do if id ~= npc.id and (not bn or n > bn) then best, bn = id, n end end
	if best and bn >= 2 and not mem[best] and math.random() < 0.55 then return byId[best] end
	if math.random() < 0.45 then return "skip" end
	return pick(others)
end
local function npcKill(npc, my)
	for _, v in pairs(my.choices) do if type(v) == "number" and byId[v].alive then return byId[v] end end
	local threats = {}
	for voter, tgt in pairs(lastVotes) do
		local vt, tg = byId[voter], type(tgt) == "number" and byId[tgt]
		if vt and vt.alive and vt.role ~= "Eliminator" and tg and tg.role == "Eliminator" then table.insert(threats, vt) end
	end
	if #threats > 0 and math.random() < 0.75 then return pick(threats) end
	return pick(alive(function(x) return x.role ~= "Eliminator" end))
end
local function npcCheck(npc)
	local mem = known[npc.id] or {}
	local c = alive(function(x) return x.id ~= npc.id and not mem[x.id] end)
	table.sort(c, function(a, b) return S(npc, a.id) > S(npc, b.id) end)
	if #c == 0 then return nil end
	return (S(npc, c[1].id) > 0.5) and c[1] or pick(c)
end
local function npcHeal(npc)
	if math.random() < 0.3 then return npc end
	return pick(alive(function(x) return x.id ~= npc.id end)) or npc
end
local function learnFromVote(out, choices)
	for voter, tgt in pairs(choices) do
		if tgt == out.id then for _, n in ipairs(npcsAlive()) do if n.id ~= voter then addS(n, voter, out.role == "Eliminator" and -1.5 or 1.2) end end
		elseif tgt == "skip" and out.role == "Eliminator" then for _, n in ipairs(npcsAlive()) do if n.id ~= voter then addS(n, voter, 0.5) end end end
	end
end

-- selection
local rate = {}
evAction.OnServerEvent:Connect(function(plr, action, a)
	local now = os.clock(); local r = rate[plr]
	if not r or now - r.t > 1 then r = {t = now, n = 0}; rate[plr] = r end
	r.n += 1; if r.n > 12 then return end
	local pt = ptOf(plr); if not pt or not pt.alive or not sel then return end
	if action == "select" and sel.allowed[pt.id] then
		if a == "skip" then if sel.kind == "vote" then sel.choices[pt.id] = "skip"; RS:WaitForChild("DarkRoomValidAction"):Fire(plr, "skip"); if sel.onChoice then sel.onChoice(pt, "skip") end end return end
		local tg = byId[tonumber(a) or -1]
		if tg and tg.alive and sel.valid(pt, tg) then sel.choices[pt.id] = tg.id; RS:WaitForChild("DarkRoomValidAction"):Fire(plr, tg.id); if sel.onChoice then sel.onChoice(pt, tg) end end
	elseif action == "confirm" and sel.confirmFrom == pt.id and sel.answer == nil then sel.answer = (a == true); RS:WaitForChild("DarkRoomValidAction"):Fire(plr) end
end)
local function runSelection(kind, actors, timeout, valid, onChoice, npcPick)
	sel = {kind = kind, allowed = {}, choices = {}, valid = valid, onChoice = onChoice}
	local my = sel
	for _, pt in ipairs(actors) do sel.allowed[pt.id] = true end
	cue(actors, "select", {kind = kind, timeout = timeout}); RS:WaitForChild("DarkRoomPhase"):Fire(kind)
	for _, pt in ipairs(actors) do
		if not pt.player then
			task.delay(1.2 + math.random() * 1.8, function()
				if sel ~= my then return end
				local t = npcPick and npcPick(pt, my)
				if t == "skip" then my.choices[pt.id] = "skip"; if onChoice then onChoice(pt, "skip") end
				elseif t and t.alive and valid(pt, t) then my.choices[pt.id] = t.id; if onChoice then onChoice(pt, t) end end
			end)
		end
	end
	local endT = os.clock() + timeout
	while os.clock() < endT do
		local all = true
		for _, pt in ipairs(actors) do if my.choices[pt.id] == nil then all = false end end
		if all and not my.waiting then task.wait(1); break end
		task.wait(0.2)
	end
	cue(actors, "select_end"); sel = nil
	return my
end

local dayN = 0
local function intro()
	cue(nil, "choosing"); task.wait(5); cue(nil, "choosing_done")
	local byRole = {} for _, pt in ipairs(P) do byRole[pt.role] = byRole[pt.role] or pt end
	local dS = say("sleep"); local closeAt = dS * 0.6
	local gapH = math.max(len("hmm"), 1.2) + 0.5
	local revealIn = (dS - closeAt) + 0.8 + gapH + len("them") + 0.8 + len("sheriffPick") + 0.7 + len("doctorPick") + 0.5
	task.delay(closeAt, function() cue(nil, "sleep"); cue(nil, "reveal_in", revealIn) end)
	task.wait(dS + 0.8)
	faceToward(P[math.random(#P)].model)
	say("hmm"); task.wait(gapH)
	task.wait(say("them") + 0.8)
	local d = say("sheriffPick"); task.delay(d * 0.7, function() faceToward(P[math.random(#P)].model) end); task.wait(d + 0.7)
	d = say("doctorPick"); task.delay(d * 0.65, function() faceToward(P[math.random(#P)].model) end); task.wait(d + 0.5)
	cue(nil, "reveal"); task.wait(6)
	d = say("cityWakes"); cue(nil, "wake"); faceToward(nil); task.wait(d + 2)
end

local function doVote()
	dayN += 1
	announce("DAY " .. dayN); task.wait(1.6)
	task.wait(say("timeToVote") + 0.3); say("chooseVote")
	local voters = alive()
	local function list(ch)
		local counts, l = tallyOf(ch), {}
		for _, pt in ipairs(voters) do if counts[pt.id] then table.insert(l, {name = pt.name, n = counts[pt.id]}) end end
		local sk = 0 for _, v in pairs(ch) do if v == "skip" then sk += 1 end end
		if sk > 0 then table.insert(l, {name = "skip", n = sk}) end
		table.sort(l, function(a, b) return a.n > b.n end)
		return counts, l, sk
	end
	local res = runSelection("vote", voters, T.vote, function(a, t) return t.id ~= a.id end,
		function() if sel then local _, l = list(sel.choices); cue(voters, "tally", l) end end, npcVote)
	cue(nil, "tally", {})
	lastVotes = table.clone(res.choices)
	local counts, _, sk = list(res.choices)
	local best, bestN, tie = nil, sk, false
	for id, n in pairs(counts) do if n > bestN then best, bestN, tie = id, n, false elseif n == bestN then tie = true end end
	if not best or tie then announce(tie and "a tie. nobody leaves." or "the city skipped."); task.wait(3) return end
	local out = byId[best]
	faceToward(out.model)
	announce(out.name .. " was voted out."); task.wait(1.2)
	markDead(out); learnFromVote(out, res.choices)
	local key = out.role == "Eliminator" and "outElim" or out.role == "Doctor" and "outDoctor" or out.role == "Sheriff" and "outSheriff" or "outClear"
	task.wait(say(key) + 0.6)
	if out.player then task.wait(say("goSleep", {out}) + 0.3) end
	faceToward(nil)
end

local function doNight()
	announce("NIGHT " .. (dayN + 1)); mood(true)
	task.wait(say("citySleeps") + 1.2); cue(alive(), "sleep")

	-- eliminators
	local elims = alive(function(p) return p.role == "Eliminator" end)
	task.wait(say("elimWake") + 0.4); cue(elims, "wake"); say("chooseKill")
	local first
	local function push(s) local ids = {} for _, v in pairs(s.choices) do if type(v) == "number" then ids[v] = true end end local l = {} for id in pairs(ids) do table.insert(l, id) end cue(elims, "highlight", l) end
	local res = runSelection("kill", elims, T.elim, function(a, t) return t.role ~= "Eliminator" end, function(pt, tg)
		local s = sel; if not s then return end
		push(s)
		if not first then first = {pt = pt, tg = tg} return end
		if pt.id ~= first.pt.id and tg.id ~= first.tg.id and not s.asked then
			s.asked, s.waiting, s.confirmFrom = true, true, pt.id
			task.spawn(function()
				if pt.player then
					evCue:FireClient(pt.player, "confirm", {text = "Do you want to change the person to " .. first.tg.name .. "?"})
					local t0 = os.clock(); while s.answer == nil and os.clock() - t0 < T.confirm and sel == s do task.wait(0.1) end
					evCue:FireClient(pt.player, "confirm_end")
				else task.wait(1); s.answer = true end
				if s.answer == true then s.choices[pt.id] = first.tg.id; push(s) end
				s.waiting = false
			end)
		end
	end, npcKill)
	local pool = {} for _, v in pairs(res.choices) do if type(v) == "number" and byId[v].alive and not table.find(pool, v) then table.insert(pool, v) end end
	local kill = #pool > 0 and byId[pool[math.random(#pool)]] or nil
	cue(elims, "highlight", {}); cue(elims, "sleep"); task.wait(say("goSleep") + 0.6)

	-- sheriff
	local sh = alive(function(p) return p.role == "Sheriff" end)
	if #sh > 0 then
		task.wait(say("sheriffWake") + 0.4); cue(sh, "wake"); say("chooseCheck")
		runSelection("check", sh, T.sheriff, function(a, t) return t.id ~= a.id end, function(pt, tg)
			if pt.player then evCue:FireClient(pt.player, "check_result", {name = tg.name, result = tg.role == "Eliminator" and "eliminator" or tg.role == "Doctor" and "doctor" or "clear"})
			else known[pt.id] = known[pt.id] or {}; known[pt.id][tg.id] = tg.role end
		end, npcCheck)
		task.wait(2)
		cue(sh, "sleep"); task.wait(say("goSleep") + 0.6)
	else
		announce("there is no sheriff..."); task.wait(2.6)
	end

	-- doctor
	local doc = alive(function(p) return p.role == "Doctor" end)
	local healId
	if #doc > 0 then
		task.wait(say("doctorWake") + 0.4); cue(doc, "wake"); say("chooseHeal")
		local r = runSelection("heal", doc, T.doctor, function() return true end, nil, npcHeal)
		for _, v in pairs(r.choices) do healId = v end
		task.wait(0.8)
		cue(doc, "sleep"); task.wait(say("goSleep") + 0.6)
	else
		announce("there is no doctor..."); task.wait(2.6)
	end

	-- resolve
	local died
	if kill and kill.alive and kill.id ~= healId then
		died = kill; markDead(died)
		local lv = lastVotes[died.id]
		if type(lv) == "number" then for _, n in ipairs(npcsAlive()) do addS(n, lv, 0.6) end end
		if died.player then task.wait(say("goSleep", {died}) + 0.3) end
	end
	task.wait(0.8); mood(false)
	local d = say("cityWakes"); cue(alive(), "wake"); task.wait(d + 0.3)
	if died then faceToward(died.model) end
	announce(died and (died.name .. " didn't make it through the night.") or "everyone made it through the night.")
	task.wait(3.2); faceToward(nil)
end

local function runRound()
	buildParticipants()
	if #P < 3 then task.wait(5) return end
	susp, known, lastVotes, dayN, roundEnded = {}, {}, {}, 0, false
	for _, pt in ipairs(P) do saveLook(pt) end
	mood(false); buildHost(); task.wait(0.3)
	local order = table.clone(P)
	for _, pt in ipairs(order) do
		local boosted = pt.player and pt.player:GetAttribute("ElimBoost") == true
		local w = boosted and (1 + 0.05 * #P) or 1
		pt.key = math.random() ^ (1 / w)
	end
	table.sort(order, function(a, b) return a.key > b.key end)
	local idx, nElim = 1, (#P >= 6) and 2 or 1
	for _ = 1, nElim do if order[idx] then order[idx].role = "Eliminator"; idx += 1 end end
	if order[idx] then order[idx].role = "Sheriff"; idx += 1 end
	if order[idx] then order[idx].role = "Doctor"; idx += 1 end
	for i = idx, #order do order[i].role = "Innocent" end
	for _, pt in ipairs(P) do
		if pt.player then
			local partners = {}
			if pt.role == "Eliminator" then for _, o in ipairs(P) do if o.role == "Eliminator" and o ~= pt then table.insert(partners, o.name) end end end
			evRole:FireClient(pt.player, pt.role, partners)
		end
	end
	intro()
	local w
	repeat
		doNight(); w = winner()
		if not w then doVote(); w = winner() end
	until w
	local roster = {} for _, pt in ipairs(P) do table.insert(roster, {name = pt.name, role = pt.role, alive = pt.alive}) end
	roundEnded = true; cue(nil, "end", {winner = w, roster = roster, next = T.ending})
	task.wait(T.ending); restoreAll(); RS:WaitForChild("DarkRoomMatchOver"):Fire(); return true
end

local reviveFn = RS:WaitForChild("DarkRoomRevive")
reviveFn.OnInvoke = function(plr)
	local pt = ptOf(plr)
	if not pt or pt.alive or roundEnded then return false end
	pt.alive = true
	for _, e in ipairs(pt.saved or {}) do if e.p.Parent then e.p.Color = e.c; e.p.Transparency = e.t end end
	if pt.neck then pt.neck.C0 = pt.neckC0 end
	evCue:FireClient(plr, "revived")
	announce(pt.name .. " came back.")
	return true
end
RS:WaitForChild("DarkRoomLeave").Event:Connect(function(plr)
	for _, pt in ipairs(P) do if pt.player == plr then pt.player = nil; if pt.alive then markDead(pt) end end end
end)
local running = false
started.Event:Connect(function() if running then return end running = true; task.wait(1.2); while true do if runRound() then break end end; running = false end)
