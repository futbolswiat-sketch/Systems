

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Items = require(Shared.Items)
local Rarities = require(Shared.Rarities)
local Audio = require(Shared.Audio)
local Types = require(Shared.Types)

local CELL_WIDTH = 132
local CELL_PITCH = 144
local CLIP_WIDTH = 756
local POOL_SIZE = 9
local CENTER = UDim2.fromScale(0.5, 0.5)
local random = Random.new()

type Cell = {
	frame: CanvasGroup,
	name: TextLabel,
	tier: TextLabel,
	gradient: UIGradient,
	outline: UIStroke,
	emblem: Frame,
	assigned: number,
}

type Session = {
	result: Types.RollResult,
	item: Items.Item,
	color: Color3,
	elapsed: number,
	duration: number,
	spinDuration: number,
	landing: number,
	landed: boolean,
	closed: boolean,
	sequence: { [number]: Items.Item },
	instances: { Instance },
	tweens: { Tween },
	orbs: { Part },
	letters: { TextLabel },
	letterCount: number,
	worldOrigin: Part?,
	emitter: ParticleEmitter?,
	camera: Camera,
	fov: number,
	humanoid: Humanoid?,
	offset: Vector3,
	lastTick: number,
	tickAt: number,
}

type References = {
	stage: Frame,
	content: Frame,
	fit: UIScale,
	dim: Frame,
	wash: Frame,
	flash: Frame,
	burst: Frame,
	reel: Frame,
	clip: Frame,
	reelScale: UIScale,
	header: TextLabel,
	status: TextLabel,
	card: CanvasGroup,
	cardScale: UIScale,
	title: Frame,
	item: TextLabel,
	odds: TextLabel,
	badge: Frame,
	badgeLabel: TextLabel,
	skip: TextButton,
	barTop: Frame,
	barBottom: Frame,
	aura: Frame,
}

type State = {
	gui: ScreenGui,
	ui: References,
	pool: { Cell },
	current: Session?,
	connection: RBXScriptConnection?,
	skipConnection: RBXScriptConnection?,
buttonConnections: { RBXScriptConnection },
	tickSound: Sound,
	reducedMotion: boolean,
	destroyed: boolean,
}

local RollController = {}
RollController.__index = RollController
export type Controller = typeof(setmetatable({} :: State, RollController))


local function child(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)
	assert(found, string.format("Missing reveal template: %s.%s", parent:GetFullName(), name))
	return found
end

local function commas(value: number): string
	local text = string.format("%.0f", value):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return if text:sub(1, 1) == "," then text:sub(2) else text
end

local function paint(emblem: Instance, color: Color3, motif: number)
	for i = 1, 3 do
		local shape = child(emblem, "Sigil" .. i) :: Frame
		shape.BackgroundColor3 = color
		shape.Rotation = if motif % 2 == 0 then i * 30 else 45
		local corner = shape:FindFirstChildOfClass("UICorner")
		local outline = shape:FindFirstChildOfClass("UIStroke")
		if corner then corner.CornerRadius = UDim.new(0, if motif == 2 then 100 else 3) end
		if outline then outline.Color = color end
	end
	;(child(emblem, "Core") :: Frame).BackgroundColor3 = color:Lerp(Theme.Highlight, 0.45)
end

local function configure(cell: Cell, item: Items.Item)
	local rarity = Rarities[item.tier]
	cell.name.Text = item.name
	cell.tier.Text = rarity.name:upper()
	cell.tier.TextColor3 = rarity.color
	cell.outline.Color = rarity.color
	cell.gradient.Color = ColorSequence.new(rarity.color:Lerp(Theme.Base, 0.4), Theme.Base)
	paint(cell.emblem, rarity.color, item.motif)
end

local function tween(session: Session, object: Instance, duration: number, style: Enum.EasingStyle, properties: { [string]: unknown }): Tween
	local animation = TweenService:Create(object, TweenInfo.new(duration, style, Enum.EasingDirection.Out), properties)
	table.insert(session.tweens, animation)
	animation:Play()
	return animation
end

local function track(session: Session, object: Instance)
	table.insert(session.instances, object)
end

local function sound(session: Session, id: string, volume: number, pitch: number)
	local voice = Instance.new("Sound")
	voice.Name = "RelicRevealVoice"
	voice.SoundId = id
	voice.Volume = math.clamp(volume, 0, 0.65)
	voice.PlaybackSpeed = pitch
	voice.Parent = SoundService
	track(session, voice)
	voice:Play()
end

function RollController.new(gui: ScreenGui): Controller
	local stage = child(gui, "Stage") :: Frame
	local content = child(stage, "Content") :: Frame
	local reel = child(content, "Reel") :: Frame
	local card = child(content, "Card") :: CanvasGroup
	local badge = child(card, "Badge") :: Frame
	local refs: References = {
		stage = stage, content = content, fit = child(content, "Fit") :: UIScale,
		dim = child(stage, "Dim") :: Frame, wash = child(stage, "Wash") :: Frame,
		flash = child(stage, "Flash") :: Frame, burst = child(stage, "Burst") :: Frame,
		reel = reel, clip = child(reel, "Clip") :: Frame,
		reelScale = child(reel, "ReelScale") :: UIScale,
		header = child(content, "Header") :: TextLabel, status = child(content, "Status") :: TextLabel,
		card = card, cardScale = child(card, "CardScale") :: UIScale,
		title = child(card, "TitleHolder") :: Frame,
		item = child(card, "ItemName") :: TextLabel, odds = child(card, "Odds") :: TextLabel,
		badge = badge, badgeLabel = child(badge, "Label") :: TextLabel,
		skip = child(child(stage, "SkipHolder"), "Skip") :: TextButton,
		barTop = child(stage, "BarTop") :: Frame, barBottom = child(stage, "BarBottom") :: Frame,
		aura = child(content, "Aura") :: Frame,
	}
	local tickSound = Instance.new("Sound")
	tickSound.Name = "VesperReelTick"
	tickSound.SoundId = Audio[1].chime
	tickSound.Volume = 0.045
	tickSound.PlaybackSpeed = 2.4
	tickSound.Parent = SoundService
	local self: Controller = setmetatable({
		gui = gui, ui = refs, pool = {}, current = nil, connection = nil,
		skipConnection = nil, buttonConnections = {}, tickSound = tickSound, reducedMotion = false, destroyed = false,
	}, RollController)
	local template = child(child(gui, "Templates"), "Cell") :: CanvasGroup
	
	for i = 1, POOL_SIZE do
		local cell = template:Clone()
		cell.Name = "RecycledCell" .. i
		cell.Visible = true
		cell.GroupColor3 = Color3.new(1, 1, 1)
		local background = Instance.new("Frame")
		background.Name = "CardBackground"
		background.Size, background.BackgroundColor3 = UDim2.fromScale(1, 1), Color3.new(1, 1, 1)
		background.ZIndex, background.BorderSizePixel = 1, 0
		local gradient = child(cell, "UIGradient") :: UIGradient
		gradient.Parent = background
		background.Parent = cell
		cell.BackgroundTransparency = 1
		;(child(cell, "NameLabel") :: TextLabel).TextColor3 = Theme.Text
		cell.Parent = refs.clip
		table.insert(self.pool, {
			frame = cell, name = child(cell, "NameLabel") :: TextLabel,
			tier = child(cell, "TierLabel") :: TextLabel,
			gradient = gradient,
			outline = child(cell, "UIStroke") :: UIStroke,
			emblem = child(cell, "Emblem") :: Frame, assigned = -1000,
		})
	end
	refs.stage.Visible = false
	local buttonScale = refs.skip:FindFirstChildOfClass("UIScale")
	if buttonScale then
		local hoverTween: Tween? = nil
		local function scaleButton(value: number)
			if hoverTween then hoverTween:Cancel() end
			hoverTween = TweenService:Create(buttonScale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = value })
			hoverTween:Play()
		end
		table.insert(self.buttonConnections, refs.skip.MouseEnter:Connect(function() scaleButton(1.04) end))
		table.insert(self.buttonConnections, refs.skip.MouseLeave:Connect(function() scaleButton(1) end))
		table.insert(self.buttonConnections, refs.skip.MouseButton1Down:Connect(function() scaleButton(0.96) end))
		table.insert(self.buttonConnections, refs.skip.MouseButton1Up:Connect(function() scaleButton(1) end))
	end
	self.skipConnection = refs.skip.Activated:Connect(function() self:skip() end)
	self.connection = RunService.RenderStepped:Connect(function(dt: number) self:_step(dt) end)
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({ tickSound }) end)
	end)
	return self
end

function RollController.isBusy(self: Controller): boolean
	return self.current ~= nil
end

function RollController.setReducedMotion(self: Controller, enabled: boolean)
	self.reducedMotion = enabled
end

function RollController._caption(self: Controller, text: string)
	self.ui.skip.Text = text
	local caption = self.ui.skip:FindFirstChild("Caption")
	if caption and caption:IsA("TextLabel") then caption.Text = text end
end

function RollController.cancel(self: Controller)
	local session = self.current
	if not session or session.closed then return end
	session.closed = true
	self.current = nil
	for _, animation in session.tweens do animation:Cancel() end
	for _, object in session.instances do object:Destroy() end
	session.camera.FieldOfView = session.fov
	if session.humanoid and session.humanoid.Parent then session.humanoid.CameraOffset = session.offset end
	self.tickSound:Stop()
	self.ui.stage.Visible = false
	self.ui.content.Position = CENTER
	self.ui.barTop.Position = UDim2.fromScale(0, -0.12)
	self.ui.barBottom.Position = UDim2.fromScale(0, 1)
end

function RollController.destroy(self: Controller)
	if self.destroyed then return end
	self:cancel()
	self.destroyed = true
	if self.connection then self.connection:Disconnect() end
	if self.skipConnection then self.skipConnection:Disconnect() end
for _, connection in self.buttonConnections do connection:Disconnect() end
	for _, cell in self.pool do cell.frame:Destroy() end
	self.tickSound:Destroy()
end

function RollController._world(self: Controller, session: Session)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then return end
	local folder = Instance.new("Folder")
	folder.Name = "VesperRevealEffects"
	folder.Parent = session.camera
	track(session, folder)
	local function part(name: string, size: Vector3): Part
		local p = Instance.new("Part")
		p.Name, p.Size = name, size
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.CastShadow, p.Material, p.Color = false, Enum.Material.Neon, session.color
		p.CFrame = root.CFrame
		p.Parent = folder
		return p
	end
	local origin = part("EmitterOrigin", Vector3.one)
	origin.Transparency = 1
	session.worldOrigin = origin
	local attachment = Instance.new("Attachment")
	attachment.Parent = origin
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(session.color, Theme.Highlight)
	emitter.LightEmission = 0.9
	emitter.Lifetime = NumberRange.new(0.5, 1.3)
	emitter.Speed = NumberRange.new(7, 19)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Parent = attachment
	session.emitter = emitter
	local budget = if UserInputService.TouchEnabled then 20 else 42
	emitter:Emit(if session.item.tier <= 2 then 10 else budget)
	if session.item.tier >= 7 then
		emitter.Rate = if UserInputService.TouchEnabled then 16 else 32
		emitter.Lifetime = NumberRange.new(0.8, 1.8)
		emitter.Speed = NumberRange.new(13, 28)
		emitter:Emit(if UserInputService.TouchEnabled then 55 else 120)
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = session.color, 26, 0
		light.Shadows, light.Parent = true, origin
		tween(session, light, 0.28, Enum.EasingStyle.Back, { Brightness = 9 })
		tween(session, light, 2.1, Enum.EasingStyle.Exponential, { Brightness = 1.2 })
	end
	if session.item.tier < 5 or self.reducedMotion then return end
	local count = if UserInputService.TouchEnabled then 6 else 10
	for i = 1, count do
		local orb = part("Orbit" .. i, Vector3.one * 0.5)
		orb.Shape = Enum.PartType.Ball
		local a = Instance.new("Attachment")
		a.Position, a.Parent = Vector3.new(0, 0.3, 0), orb
		local b = Instance.new("Attachment")
		b.Position, b.Parent = Vector3.new(0, -0.3, 0), orb
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a, b
		trail.Color = ColorSequence.new(session.color)
		trail.LightEmission, trail.Lifetime = 1, 0.4
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = orb
		table.insert(session.orbs, orb)
	end
	if session.item.tier < 7 then return end
	local sky = Instance.new("Attachment")
	sky.Position, sky.Parent = Vector3.new(0, 130, 0), origin
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = attachment, sky
	beam.FaceCamera, beam.LightEmission = true, 1
	beam.Color = ColorSequence.new(session.color, Theme.Highlight)
	beam.Width0, beam.Width1 = 0, 0
	beam.Transparency = NumberSequence.new(0.2, 0.85)
	beam.Parent = origin
	tween(session, beam, 0.45, Enum.EasingStyle.Exponential, { Width0 = 11, Width1 = 3 })

	for i = 1, 4 do
		local fork = Instance.new("Attachment")
		local angle = i * math.pi * 2 / 4 + random:NextNumber(-0.22, 0.22)
		fork.Position = Vector3.new(math.cos(angle) * 34, random:NextNumber(38, 78), math.sin(angle) * 34)
		fork.Parent = origin
		local bolt = Instance.new("Beam")
		bolt.Attachment0, bolt.Attachment1 = attachment, fork
		bolt.FaceCamera, bolt.LightEmission = true, 1
		bolt.Color = ColorSequence.new(Theme.Highlight, session.color)
		bolt.Width0, bolt.Width1 = 0, 0
		bolt.Transparency = NumberSequence.new(0.08, 1)
		bolt.Parent = origin
		tween(session, bolt, 0.22 + i * 0.04, Enum.EasingStyle.Exponential, { Width0 = 2.2, Width1 = 0.35 })
	end
end

function RollController._supernova(self: Controller, session: Session)
	if self.reducedMotion or session.item.tier < 5 then return end
	local ui = self.ui
	local tier = session.item.tier
	local shardCount = if UserInputService.TouchEnabled then 12 elseif tier >= 9 then 28 else 18
	local symbols = { "✦", "✧", "◆", "✦", "✧" }

	for i = 1, shardCount do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(0.22, if tier >= 9 then 0.66 else 0.46)
		local shard = Instance.new("TextLabel")
		shard.Name, shard.Text = "RelicGlyph", symbols[random:NextInteger(1, #symbols)]
		shard.AnchorPoint, shard.Position = Vector2.new(0.5, 0.5), CENTER
		shard.Size, shard.BackgroundTransparency = UDim2.fromOffset(random:NextInteger(22, 54), random:NextInteger(22, 54)), 1
		shard.Font, shard.TextScaled, shard.TextColor3 = Theme.TitleFont, true, session.color:Lerp(Theme.Highlight, random:NextNumber(0.1, 0.75))
		shard.TextTransparency, shard.ZIndex = 0.08, 8
		shard.Parent = ui.stage
		track(session, shard)
		local endPosition = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.5 + math.sin(angle) * distance)
		shard.Rotation = random:NextInteger(-80, 80)
		tween(session, shard, 0.8 + random:NextNumber(0, 0.55), Enum.EasingStyle.Exponential, {
			Position = endPosition,
			Rotation = shard.Rotation + random:NextInteger(180, 520),
			TextTransparency = 1,
		})
	end

	local ringCount = if tier >= 9 then 3 else 2
	for i = 1, ringCount do
		local ring = Instance.new("Frame")
		ring.Name, ring.AnchorPoint, ring.Position = "SupernovaRing", Vector2.new(0.5, 0.5), CENTER
		ring.Size, ring.BackgroundTransparency, ring.ZIndex = UDim2.fromOffset(44 + i * 70, 44 + i * 70), 1, 7
		local corner = Instance.new("UICorner")
		corner.CornerRadius, corner.Parent = UDim.new(1, 0), ring
		local stroke = Instance.new("UIStroke")
		stroke.Color, stroke.Thickness, stroke.Transparency, stroke.Parent = session.color, 8 - i * 1.5, 0.12, ring
		ring.Parent = ui.stage
		track(session, ring)
		tween(session, ring, 0.75 + i * 0.18, Enum.EasingStyle.Exponential, {
			Size = UDim2.fromScale(1.2 + i * 0.28, 1.2 + i * 0.28),
			Rotation = i * 70,
		})
		tween(session, stroke, 0.75 + i * 0.18, Enum.EasingStyle.Exponential, { Transparency = 1, Thickness = 0 })
	end

	if tier >= 7 then
		ui.aura.BackgroundColor3 = session.color
		ui.aura.BackgroundTransparency = 0.72
		tween(session, ui.aura, 1.1, Enum.EasingStyle.Exponential, { BackgroundTransparency = 1 })
	end
end

function RollController._land(self: Controller, session: Session)
	if session.landed or session.closed then return end
	session.landed = true
	local ui = self.ui
	local tier = session.item.tier
	ui.reel.Visible, ui.card.Visible = false, true
	ui.header.Text = ""
	ui.status.Text = ""
	ui.card.GroupTransparency = 0
	ui.cardScale.Scale = if tier >= 9 then 0.08 else 0.35
	ui.item.Text = session.item.name
	ui.item.TextTransparency = 0
	ui.odds.Text = "1 IN " .. commas(session.result.effectiveOdds) .. "  /  THIS RELIC AT ROLL LUCK"
	ui.badge.Visible = true
	ui.badgeLabel.Text = if session.result.newDiscovery then "NEW DISCOVERY" else "COLLECTION +1"
	ui.badgeLabel.TextColor3 = Theme.Accent2
	;(child(ui.card, "UIStroke") :: UIStroke).Color = session.color
	paint(child(ui.card, "Emblem"), session.color, session.item.motif)
	local style = if tier <= 2 then Enum.EasingStyle.Back elseif tier <= 4 then Enum.EasingStyle.Elastic else Enum.EasingStyle.Exponential
	tween(session, ui.cardScale, if tier <= 2 then 0.3 else 0.65, style, { Scale = 1 })
	ui.wash.BackgroundColor3 = session.color
	ui.wash.BackgroundTransparency = if tier <= 2 then 1 else 0.7
	tween(session, ui.wash, 0.8, Enum.EasingStyle.Exponential, { BackgroundTransparency = 0.95 })
	local name = Rarities[tier].name:upper()
	for i = 1, #name do
		local letter = Instance.new("TextLabel")
		letter.Name, letter.Text, letter.LayoutOrder = "RarityLetter", name:sub(i, i), i
		letter.AutomaticSize = Enum.AutomaticSize.XY
		letter.Size, letter.BackgroundTransparency = UDim2.fromOffset(0, 0), 1
		letter.Font, letter.TextSize, letter.TextColor3 = Theme.TitleFont, if #name > 10 then 48 else 58, session.color
		letter.TextTransparency, letter.ZIndex = 1, 6
		local scale = Instance.new("UIScale")
		scale.Scale, scale.Parent = 2, letter
		letter.Parent = ui.title
		track(session, letter)
		table.insert(session.letters, letter)
	end
	self:_caption("CONTINUE  [X]")
	self:_world(session)
	self:_supernova(session)
	local audio = Audio[tier]
	sound(session, audio.chime, audio.volume, audio.pitch)
	if tier >= 5 then sound(session, audio.impact, audio.volume * 0.8, 0.7) end
	if tier >= 3 then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity, bloom.Threshold, bloom.Parent = if self.reducedMotion then 0.1 else 0.6, 1.5, session.camera
		track(session, bloom)
		tween(session, bloom, 1.2, Enum.EasingStyle.Exponential, { Intensity = 0 })
	end
	if tier >= 5 and not self.reducedMotion then
		tween(session, session.camera, 0.22, Enum.EasingStyle.Back, { FieldOfView = session.fov - 9 })
		ui.burst.Visible = true
		for index, ray in ui.burst:GetChildren() do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = session.color
				ray.BackgroundTransparency = 0.15
				ray.Rotation = index * (360 / math.max(1, #ui.burst:GetChildren()))
				tween(session, ray, 0.7 + index * 0.015, Enum.EasingStyle.Exponential, {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1.8, 0.09),
				})
			end
		end
		local ring = Instance.new("Frame")
		ring.Name, ring.AnchorPoint, ring.Position = "RevealShockwave", Vector2.new(0.5, 0.5), CENTER
		ring.Size, ring.BackgroundTransparency, ring.ZIndex = UDim2.fromOffset(120, 120), 1, 3
		local corner = Instance.new("UICorner")
		corner.CornerRadius, corner.Parent = UDim.new(1, 0), ring
		local outline = Instance.new("UIStroke")
		outline.Color, outline.Thickness, outline.Parent = session.color, 6, ring
		ring.Parent = ui.content
		track(session, ring)
		tween(session, ring, 0.85, Enum.EasingStyle.Exponential, { Size = UDim2.fromOffset(1100, 1100) })
		tween(session, outline, 0.85, Enum.EasingStyle.Exponential, { Transparency = 1, Thickness = 0 })
		ui.flash.BackgroundColor3 = if tier >= 7 then Theme.Highlight else session.color
		ui.flash.BackgroundTransparency = 0.75
		tween(session, ui.flash, 0.3, Enum.EasingStyle.Exponential, { BackgroundTransparency = 1 })
		if tier >= 7 then
			task.delay(0.16, function()
				if not session.closed then
					ui.flash.BackgroundTransparency = 0.86
					tween(session, ui.flash, 0.28, Enum.EasingStyle.Exponential, { BackgroundTransparency = 1 })
				end
			end)
		end
		if session.humanoid then tween(session, session.humanoid, 0.5, Enum.EasingStyle.Exponential, { CameraOffset = session.offset + Vector3.new(0, 0.3, -1) }) end
	end
end

function RollController.play(self: Controller, result: Types.RollResult, quick: boolean)
	if self.destroyed then return end
	local item = Items.ById[result.itemId]
	if not item or result.tier ~= item.tier then return end
	self:cancel()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local tier = item.tier
	local shouldQuickReveal = quick and tier <= 4
	local spin = if shouldQuickReveal then 0 else if tier <= 4 then 0.7 elseif tier <= 6 then 1.8 else 3.2
	local duration = if shouldQuickReveal then 0.7 else math.max(Rarities[tier].duration, spin + 0.7)
	local session: Session = {
		result = result, item = item, color = Rarities[tier].color, elapsed = 0,
		duration = duration, spinDuration = spin, landing = if tier >= 7 then 38 else 22,
		landed = false, closed = false, sequence = {}, instances = {}, tweens = {},
		orbs = {}, letters = {}, letterCount = 0, worldOrigin = nil, emitter = nil,
		camera = camera, fov = camera.FieldOfView, humanoid = humanoid,
		offset = if humanoid then humanoid.CameraOffset else Vector3.zero,
		lastTick = -1, tickAt = 0,
	}

	for i = -5, session.landing + 6 do session.sequence[i] = Items.List[random:NextInteger(1, #Items.List)] end
	session.sequence[session.landing] = item
	for _, cell in self.pool do cell.assigned = -1000 end
	self.current = session
	local ui = self.ui
	ui.stage.Visible, ui.reel.Visible, ui.card.Visible = true, spin > 0, false
	ui.reelScale.Scale = 1
	ui.header.Text, ui.header.TextTransparency = "THE ALTAR IS LISTENING", 0
	;(child(ui.header, "UIStroke") :: UIStroke).Transparency = 0
	ui.status.Text, ui.status.TextTransparency = "SUMMONING SOMETHING EXTRAORDINARY", 0
	ui.dim.BackgroundTransparency = if tier >= 7 then 0.35 elseif tier >= 5 then 0.6 else 0.9
	ui.flash.BackgroundTransparency, ui.wash.BackgroundTransparency = 1, 1
	ui.burst.Visible, ui.aura.BackgroundTransparency = false, 1
	for _, ray in ui.burst:GetChildren() do
		if ray:IsA("Frame") then
			ray.AnchorPoint, ray.Position = Vector2.new(0.5, 0.5), CENTER
			ray.Size, ray.BackgroundTransparency = UDim2.fromScale(0.12, 0.04), 1
		end
	end
	self:_caption("SKIP REVEAL  [X]")
	if tier >= 7 then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name, grade.Brightness, grade.TintColor = "RollCinematicGrade", 0, Theme.Text
		grade.Parent = camera
		track(session, grade)
		tween(session, grade, 0.8, Enum.EasingStyle.Exponential, { Brightness = -0.25, TintColor = session.color:Lerp(Theme.Text, 0.65) })
		if not self.reducedMotion then
			local blur = Instance.new("BlurEffect")
			blur.Size, blur.Parent = 0, camera
			track(session, blur)
			tween(session, blur, 0.6, Enum.EasingStyle.Exponential, { Size = 5 })
			local depth = Instance.new("DepthOfFieldEffect")
			depth.FarIntensity, depth.NearIntensity = 0.3, 0
			depth.FocusDistance, depth.InFocusRadius, depth.Parent = 15, 25, camera
			track(session, depth)
		end
		tween(session, ui.barTop, 0.4, Enum.EasingStyle.Exponential, { Position = UDim2.fromScale(0, 0) })
		tween(session, ui.barBottom, 0.4, Enum.EasingStyle.Exponential, { Position = UDim2.fromScale(0, 0.88) })
	end
	if spin == 0 then self:_land(session) end
end

function RollController.skip(self: Controller)
	local session = self.current
	if not session then return end
	if session.landed then self:cancel(); return end
	self:_land(session)
	session.elapsed = session.duration - 0.45
end

function RollController._step(self: Controller, dt: number)
	local ui = self.ui
	local viewport = self.gui.AbsoluteSize
	ui.fit.Scale = math.clamp(math.min(viewport.X / 940, viewport.Y / 600), 0.35, 1.2)
	local session = self.current
	if not session then return end
	session.elapsed += dt
	if session.elapsed >= session.duration then self:cancel(); return end
	if not session.landed then
		local progress = math.clamp(session.elapsed / session.spinDuration, 0, 1)
		local position = session.landing * TweenService:GetValue(progress, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
		local first = math.floor(position) - 4
		for index = first, first + POOL_SIZE - 1 do
			local cell = self.pool[(index % POOL_SIZE) + 1]
			local item = session.sequence[index]
			if item and cell.assigned ~= index then configure(cell, item); cell.assigned = index end
			local offset = index - position
			cell.frame.Position = UDim2.fromOffset(CLIP_WIDTH / 2 + offset * CELL_PITCH - CELL_WIDTH / 2, 11)
			cell.frame.GroupTransparency = math.clamp(math.abs(offset) * 0.13, 0, 0.7)
		end
		local tick = math.floor(position)
		if tick ~= session.lastTick and os.clock() - session.tickAt > 0.07 then
			session.tickAt, session.lastTick = os.clock(), tick
			self.tickSound.TimePosition = 0
			self.tickSound:Play()
		end
		if progress >= 1 then self:_land(session) end
	else
		local age = math.max(0, session.elapsed - session.spinDuration)
		local count = if session.item.tier < 5 then #session.letters else math.min(#session.letters, math.floor(age / 0.055) + 1)
		for i = session.letterCount + 1, count do
			local letter = session.letters[i]
			letter.TextTransparency = 0
			tween(session, child(letter, "UIScale"), 0.28, Enum.EasingStyle.Back, { Scale = 1 })
		end
		session.letterCount = count
		local shake = if self.reducedMotion or session.item.tier < 3 then 0 else math.exp(-age * 8) * 5
		ui.content.Position = UDim2.new(0.5, math.sin(age * 73) * shake, 0.5, math.cos(age * 57) * shake)
		ui.card.Rotation = if self.reducedMotion or session.item.tier < 7 then 0 else math.sin(age * 5.5) * 1.25
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			if session.worldOrigin then session.worldOrigin.CFrame = root.CFrame end
			for i, orb in session.orbs do
				local angle = age * (if session.item.tier >= 7 then 0.85 else 2) + i * math.pi * 2 / #session.orbs
				orb.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, angle, 0) * CFrame.new(6, math.sin(angle * 2), 0)
			end
		end
	end
end

return RollController




