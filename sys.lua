-- It's an build wall system, where you can do almost everything. E to build a wall. more in the script.
local uis = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local ts = game:GetService("TweenService")
local players = game:GetService("Players")

local player = players.LocalPlayer
local cam = workspace.CurrentCamera
local btn = script.Parent

local zone = workspace:WaitForChild("BuildZone")

local wallHeight = 12
local thickness = 1.2
local snap = 2
local maxDist = 250

local active = false
local mouseDown = false
local pos1 = nil
local pos2 = nil

local ghostWall = nil
local ghostCorner = nil
local cursorPart = nil

local history = {}

local colors = {
	Color3.fromRGB(130, 130, 135),
	Color3.fromRGB(200, 100, 100),
	Color3.fromRGB(100, 200, 100),
	Color3.fromRGB(100, 100, 200),
	Color3.fromRGB(50, 50, 50),
	Color3.fromRGB(250, 250, 240),
	Color3.fromRGB(255, 150, 50),
	Color3.fromRGB(50, 200, 255)
}

local mats = {
	Enum.Material.SmoothPlastic,
	Enum.Material.Wood,
	Enum.Material.Brick,
	Enum.Material.Concrete,
	Enum.Material.CorrodedMetal,
	Enum.Material.Neon,
	Enum.Material.Ice,
	Enum.Material.Glass
}

local colorId = 1
local matId = 1

local sndSuccess = Instance.new("Sound")
sndSuccess.SoundId = "rbxassetid://6895079853"
sndSuccess.Volume = 0.5
sndSuccess.Parent = workspace

local sndFail = Instance.new("Sound")
sndFail.SoundId = "rbxassetid://6895067215"
sndFail.Volume = 0.5
sndFail.Parent = workspace

local function roundVal(v)
	if snap == 0 then return v end
	return math.floor((v / snap) + 0.5) * snap
end

local function getHit()
	local mLoc = uis:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mLoc.X, mLoc.Y)

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = {zone}

	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, rp)

	if hit then
		local p = hit.Position
		local lockedY = zone.Position.Y + (zone.Size.Y / 2)
		return Vector3.new(roundVal(p.X), lockedY, roundVal(p.Z))
	end

	return nil
end

local function loadCursor()
	if not cursorPart then
		cursorPart = Instance.new("Part")
		cursorPart.Name = "CursorVis"
		cursorPart.Size = Vector3.new(snap, 0.2, snap)
		cursorPart.Anchored = true
		cursorPart.CanCollide = false
		cursorPart.Material = Enum.Material.Neon
		cursorPart.Color = Color3.fromRGB(255, 255, 255)
		cursorPart.Transparency = 0.5
		cursorPart.CastShadow = false
		cursorPart.Parent = workspace
	end
end

local function makeGhosts()
	if ghostWall then ghostWall:Destroy() end
	if ghostCorner then ghostCorner:Destroy() end

	ghostWall = Instance.new("Part")
	ghostWall.Name = "GWall"
	ghostWall.Anchored = true
	ghostWall.CanCollide = false
	ghostWall.Material = Enum.Material.ForceField
	ghostWall.Color = Color3.fromRGB(0, 150, 255)
	ghostWall.Transparency = 0.3
	ghostWall.CastShadow = false
	ghostWall.Parent = workspace

	ghostCorner = Instance.new("Part")
	ghostCorner.Name = "GCorner"
	ghostCorner.Shape = Enum.PartType.Cylinder
	ghostCorner.Anchored = true
	ghostCorner.CanCollide = false
	ghostCorner.Material = Enum.Material.ForceField
	ghostCorner.Color = Color3.fromRGB(0, 150, 255)
	ghostCorner.Transparency = 0.3
	ghostCorner.CastShadow = false
	ghostCorner.Parent = workspace
end

local function updateVisuals()
	if not pos1 or not pos2 or not ghostWall or not ghostCorner then return end

	local dist = (pos2 - pos1).Magnitude

	if dist > maxDist then
		local dir = (pos2 - pos1).Unit
		pos2 = pos1 + (dir * maxDist)
		dist = maxDist
	end

	local center = pos1 + ((pos2 - pos1) / 2)

	ghostWall.Size = Vector3.new(thickness, wallHeight, dist)
	ghostWall.CFrame = CFrame.lookAt(center, pos2) * CFrame.new(0, wallHeight/2, 0)

	ghostCorner.Size = Vector3.new(wallHeight, thickness, thickness)
	ghostCorner.CFrame = CFrame.new(pos1) * CFrame.new(0, wallHeight/2, 0) * CFrame.Angles(0, 0, math.rad(90))

	if dist < snap then
		ghostWall.Color = Color3.fromRGB(255, 50, 50)
		ghostCorner.Color = Color3.fromRGB(255, 50, 50)
	else
		ghostWall.Color = Color3.fromRGB(0, 150, 255)
		ghostCorner.Color = Color3.fromRGB(0, 150, 255)
	end
end

local function buildReal()
	local dist = (pos2 - pos1).Magnitude

	if dist >= snap then
		local cMat = mats[matId]
		local cCol = colors[colorId]

		local w = ghostWall:Clone()
		w.Name = "BuiltWall"
		w.Material = cMat
		w.Color = cCol
		w.Transparency = 0
		w.CanCollide = true
		w.CastShadow = true
		w.Parent = workspace

		local cA = ghostCorner:Clone()
		cA.Name = "BuiltCorner"
		cA.Material = cMat
		cA.Color = cCol
		cA.Transparency = 0
		cA.CanCollide = true
		cA.CastShadow = true
		cA.Parent = workspace

		local cB = cA:Clone()
		cB.CFrame = CFrame.new(pos2) * CFrame.new(0, wallHeight/2, 0) * CFrame.Angles(0, 0, math.rad(90))
		cB.Parent = workspace

		table.insert(history, {wall = w, corner1 = cA, corner2 = cB})
		sndSuccess:Play()

		local ti = TweenInfo.new(0.25, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		local ogWS = w.Size
		local ogCS = cA.Size

		w.Size = Vector3.new(thickness + 2, wallHeight + 2, dist)
		cA.Size = Vector3.new(wallHeight + 2, thickness + 2, thickness + 2)
		cB.Size = Vector3.new(wallHeight + 2, thickness + 2, thickness + 2)

		ts:Create(w, ti, {Size = ogWS}):Play()
		ts:Create(cA, ti, {Size = ogCS}):Play()
		ts:Create(cB, ti, {Size = ogCS}):Play()

		mouseDown = false
		ghostWall:Destroy()
		ghostCorner:Destroy()
		ghostWall = nil
		ghostCorner = nil
	else
		sndFail:Play()
	end
end

local function undo()
	if #history > 0 then
		local target = history[#history]
		if target.wall then target.wall:Destroy() end
		if target.corner1 then target.corner1:Destroy() end
		if target.corner2 then target.corner2:Destroy() end
		table.remove(history, #history)
		sndFail:Play()
	end
end

local function clearAll()
	for i, target in pairs(history) do
		if target.wall then target.wall:Destroy() end
		if target.corner1 then target.corner1:Destroy() end
		if target.corner2 then target.corner2:Destroy() end
	end
	history = {}
	sndFail:Play()
end

btn.MouseButton1Click:Connect(function()
	active = not active
	if active then
		btn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
		btn.Text = "Stop Building"
		loadCursor()
	else
		btn.BackgroundColor3 = Color3.fromRGB(50, 130, 220)
		btn.Text = "Start Building"
		if cursorPart then
			cursorPart:Destroy()
			cursorPart = nil
		end
		if mouseDown then
			mouseDown = false
			if ghostWall then ghostWall:Destroy() end
			if ghostCorner then ghostCorner:Destroy() end
			ghostWall = nil
			ghostCorner = nil
		end
	end
end)

runService.RenderStepped:Connect(function()
	if not active then return end

	local rayHit = getHit()
	if rayHit then
		if cursorPart then
			cursorPart.Position = rayHit
		end

		if mouseDown then
			pos2 = rayHit
			updateVisuals()
		end
	end
end)

uis.InputBegan:Connect(function(input, gpe)
	if gpe or not active then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local hit = getHit()
		if hit then
			mouseDown = true
			pos1 = hit
			pos2 = hit
			makeGhosts()
		end

	elseif input.KeyCode == Enum.KeyCode.E then
		if mouseDown and ghostWall and pos1 and pos2 then
			buildReal()
		end

	elseif input.KeyCode == Enum.KeyCode.Z and uis:IsKeyDown(Enum.KeyCode.LeftControl) then
		undo()

	elseif input.KeyCode == Enum.KeyCode.X then
		clearAll()

	elseif input.KeyCode == Enum.KeyCode.C then
		colorId = colorId + 1
		if colorId > #colors then colorId = 1 end
		sndSuccess:Play()

	elseif input.KeyCode == Enum.KeyCode.M then
		matId = matId + 1
		if matId > #mats then matId = 1 end
		sndSuccess:Play()

	elseif input.KeyCode == Enum.KeyCode.Up then
		wallHeight = wallHeight + 2
		if wallHeight > 60 then wallHeight = 60 end
		sndSuccess:Play()

	elseif input.KeyCode == Enum.KeyCode.Down then
		wallHeight = wallHeight - 2
		if wallHeight < 4 then wallHeight = 4 end
		sndSuccess:Play()
	end
end)

uis.InputEnded:Connect(function(input, gpe)
	if gpe then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if mouseDown then
			mouseDown = false
			if ghostWall then ghostWall:Destroy() end
			if ghostCorner then ghostCorner:Destroy() end
			ghostWall = nil
			ghostCorner = nil
		end
	end
end)