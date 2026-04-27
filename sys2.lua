local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local CFG = {
	BaseFOV = 75,
	SprintFOV = 90,
	CrouchFOV = 65,
	WalkSpeed = 10,
	SprintSpeed = 22,
	CrouchSpeed = 5,
	LeanAngle = 18,
	LeanOffset = 1.4,
	MaxStamina = 100,
	StaminaDrain = 18,
	StaminaRegen = 8,
	MouseSensitivity = UserInputService.MouseDeltaSensitivity or 0.4,
	HeadDragMultiplier = 0.04,
}

local state = {
	isSprinting = false,
	isCrouching = false,
	leanDir = 0,
	stamina = CFG.MaxStamina,
	isMenuOpen = false,
	isWindowFocused = true,
	wasInAir = false,
	focusRecoverFrame = false,
}

local camMath = {
	pitch = 0,
	yaw = 0,
	roll = 0,
	bobTime = 0,
	breathTime = 0,
	fallImpact = 0,
	currentFov = CFG.BaseFOV
}

local connections = {}
local activeEffects = {}

local function createSpring(mass, force, damping, speed)
	return {
		Target = Vector3.zero, Position = Vector3.zero, Velocity = Vector3.zero,
		Mass = mass, Force = force, Damping = damping, Speed = speed,
		Update = function(self, dt)
			local step = self.Speed * dt
			local distance = self.Target - self.Position
			local springForce = distance * self.Force
			self.Velocity = (self.Velocity + springForce / self.Mass * step) * (1 - self.Damping * step)
			self.Position = self.Position + self.Velocity * step
			return self.Position
		end
	}
end

local springs = {
	camera = createSpring(6, 40, 4.5, 5),
	sway = createSpring(4, 25, 6, 4),
	lean = createSpring(5, 30, 4, 6)
}

local function lerp(a, b, t) 
	return a + (b - a) * t 
end

local function cleanup()
	for _, conn in ipairs(connections) do
		if conn.Connected then conn:Disconnect() end
	end
	table.clear(connections)

	for _, effect in ipairs(activeEffects) do
		if effect and effect.Parent then effect:Destroy() end
	end
	table.clear(activeEffects)

	RunService:UnbindFromRenderStep("RealisticFPCameraSystem")
end

local function setupLighting()
	local dof = Lighting:FindFirstChild("CameraDOF") or Instance.new("DepthOfFieldEffect")
	dof.Name = "CameraDOF"
	dof.FocusDistance = 10
	dof.InFocusRadius = 30
	dof.NearIntensity = 0.2
	dof.FarIntensity = 0.1
	dof.Parent = Lighting
	table.insert(activeEffects, dof)

	local cc = Lighting:FindFirstChild("CameraColor") or Instance.new("ColorCorrectionEffect")
	cc.Name = "CameraColor"
	cc.Contrast = 0.15
	cc.Saturation = -0.1
	cc.TintColor = Color3.fromRGB(245, 245, 255)
	cc.Parent = Lighting
	table.insert(activeEffects, cc)

	return dof, cc
end

local function handleInputs()
	table.insert(connections, GuiService.MenuOpened:Connect(function() state.isMenuOpen = true end))
	table.insert(connections, GuiService.MenuClosed:Connect(function() 
		state.isMenuOpen = false 
		state.focusRecoverFrame = true
	end))

	table.insert(connections, UserInputService.WindowFocusReleased:Connect(function() state.isWindowFocused = false end))
	table.insert(connections, UserInputService.WindowFocused:Connect(function() 
		state.isWindowFocused = true 
		state.focusRecoverFrame = true
	end))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.LeftShift then state.isSprinting = true
		elseif input.KeyCode == Enum.KeyCode.C then state.isCrouching = not state.isCrouching
		elseif input.KeyCode == Enum.KeyCode.Q then state.leanDir = -1
		elseif input.KeyCode == Enum.KeyCode.E then state.leanDir = 1 end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.LeftShift then state.isSprinting = false
		elseif input.KeyCode == Enum.KeyCode.Q and state.leanDir == -1 then state.leanDir = 0
		elseif input.KeyCode == Enum.KeyCode.E and state.leanDir == 1 then state.leanDir = 0 end
	end))
end

local function onRenderStep(dt)
	if dt > 0.1 then dt = 0.1 end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end

	if not state.isWindowFocused or state.isMenuOpen then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		return 
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local mouseDelta = UserInputService:GetMouseDelta()

	if state.focusRecoverFrame then
		mouseDelta = Vector2.zero
		state.focusRecoverFrame = false
	end

	camMath.pitch = math.clamp(camMath.pitch - mouseDelta.Y * CFG.MouseSensitivity, -85, 85)
	camMath.yaw = camMath.yaw - mouseDelta.X * CFG.MouseSensitivity

	springs.sway.Target = Vector3.new(-mouseDelta.X * CFG.HeadDragMultiplier, -mouseDelta.Y * CFG.HeadDragMultiplier, 0)
	local swayOffset = springs.sway:Update(dt)

	local velocity = rootPart.Velocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local isMoving = horizontalSpeed > 0.5

	if state.isCrouching or state.leanDir ~= 0 or state.stamina <= 0 then
		state.isSprinting = false
	end

	if state.isSprinting and isMoving then
		state.stamina = math.max(0, state.stamina - (CFG.StaminaDrain * dt))
		humanoid.WalkSpeed = lerp(humanoid.WalkSpeed, CFG.SprintSpeed, dt * 4)
	else
		state.stamina = math.min(CFG.MaxStamina, state.stamina + (CFG.StaminaRegen * dt))
		humanoid.WalkSpeed = lerp(humanoid.WalkSpeed, state.isCrouching and CFG.CrouchSpeed or CFG.WalkSpeed, dt * 5)
	end

	local exhaustionFactor = 1 - (state.stamina / CFG.MaxStamina)
	local healthFactor = math.clamp(humanoid.Health / humanoid.MaxHealth, 0.2, 1)
	local isInjured = healthFactor < 0.5

	local breathRate = 1.2 + (exhaustionFactor * 2.5) + (isInjured and 1.5 or 0)
	camMath.breathTime = camMath.breathTime + dt * breathRate
	local breathY = math.sin(camMath.breathTime) * (0.02 + (exhaustionFactor * 0.04))
	local breathX = math.cos(camMath.breathTime * 0.5) * (0.01 + (exhaustionFactor * 0.03))

	local bobY, bobX = 0, 0
	if isMoving and humanoid:GetState() == Enum.HumanoidStateType.Running then
		local bobMultiplier = state.isSprinting and 0.6 or (state.isCrouching and 0.85 or 0.45)
		local bobIntensity = state.isSprinting and 0.4 or 0.25

		if isInjured then 
			bobMultiplier = 0.35
			bobIntensity = 0.5 
		end

		camMath.bobTime = camMath.bobTime + dt * (horizontalSpeed * bobMultiplier)

		if isInjured then
			bobY = math.abs(math.sin(camMath.bobTime)) * bobIntensity
			bobX = math.cos(camMath.bobTime) * bobIntensity 
		else
			bobY = math.abs(math.sin(camMath.bobTime)) * bobIntensity
			bobX = math.cos(camMath.bobTime * 0.5) * (bobIntensity * 0.9)
		end
	else
		camMath.bobTime = lerp(camMath.bobTime, 0, dt * 6)
	end

	local inAir = humanoid:GetState() == Enum.HumanoidStateType.Freefall
	if not inAir and state.wasInAir then
		local fallSpeed = math.abs(velocity.Y)
		if fallSpeed > 10 then
			camMath.fallImpact = math.clamp(fallSpeed * 0.2, 1, 8)
			springs.camera.Velocity = Vector3.new(0, -camMath.fallImpact, 0)
		end
	end
	state.wasInAir = inAir

	local moveDir = rootPart.CFrame:VectorToObjectSpace(velocity)
	local strafeTilt = math.clamp(-moveDir.X * 0.1, -6, 6)

	springs.lean.Target = Vector3.new(state.leanDir * CFG.LeanOffset, 0, state.leanDir * CFG.LeanAngle)
	local leanData = springs.lean:Update(dt)
	camMath.roll = lerp(camMath.roll, strafeTilt + leanData.Z, dt * 8)

	local targetHeight = state.isCrouching and -1.6 or 0
	if isInjured and not state.isCrouching then targetHeight = -0.6 end

	springs.camera.Target = Vector3.new(bobX + breathX, bobY + breathY + targetHeight, 0)
	local camOffset = springs.camera:Update(dt)

	rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, math.rad(camMath.yaw), 0)

	local head = character:FindFirstChild("Head")
	local attachPos = head and head.Position or rootPart.Position + Vector3.new(0, 1.5, 0)

	local targetCFrame = CFrame.new(attachPos)
		* CFrame.Angles(0, math.rad(camMath.yaw), 0) 
		* CFrame.new(leanData.X, 0, 0) 
		* CFrame.Angles(math.rad(camMath.pitch), 0, math.rad(camMath.roll)) 
		* CFrame.new(camOffset.X, camOffset.Y, camOffset.Z) 
		* CFrame.Angles(swayOffset.Y, swayOffset.X, 0) 

	camera.CFrame = camera.CFrame:Lerp(targetCFrame, dt * 50)

	local targetFov = CFG.BaseFOV
	if state.isSprinting and horizontalSpeed > 10 then targetFov = CFG.SprintFOV
	elseif state.isCrouching then targetFov = CFG.CrouchFOV end

	camMath.currentFov = lerp(camMath.currentFov, targetFov, dt * 5)
	camera.FieldOfView = camMath.currentFov

	local dofEffect = Lighting:FindFirstChild("CameraDOF")
	if dofEffect then
		local targetBlur = (state.isSprinting and horizontalSpeed > 16) and 0.25 or 0.05
		dofEffect.FarIntensity = lerp(dofEffect.FarIntensity, targetBlur, dt * 4)

		local rayOrigin = camera.CFrame.Position
		local rayDirection = camera.CFrame.LookVector * 100
		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection)

		if raycastResult then
			local distance = (rayOrigin - raycastResult.Position).Magnitude
			dofEffect.FocusDistance = lerp(dofEffect.FocusDistance, math.clamp(distance, 5, 50), dt * 10)
		else
			dofEffect.FocusDistance = lerp(dofEffect.FocusDistance, 50, dt * 5)
		end
	end
end

local function hideCharacter(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if part.Name == "Head" or part.Name:match("Hair") or part:IsA("Accessory") then
				part.LocalTransparencyModifier = 1
			end
		end
	end
end

local function setupCharacter(character)
	cleanup()

	camera.CameraType = Enum.CameraType.Scriptable
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	hideCharacter(character)
	setupLighting()
	handleInputs()

	table.insert(connections, character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") and (part.Name == "Head" or part.Name:match("Hair") or part:IsA("Accessory")) then
			part.LocalTransparencyModifier = 1
		end
	end))

	RunService:BindToRenderStep("RealisticFPCameraSystem", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(cleanup)
