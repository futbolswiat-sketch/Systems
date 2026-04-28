local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TargetRigName = "jojo"
local FleeDistance = 20
local StopFleeDistance = 30
local MaxSpeed = 16
local Acceleration = 10
local Responsiveness = 35
local RaycastOffset = Vector3.new(0, 4, 0)
local RaycastDirection = Vector3.new(0, -15, 0)
local WalkAnimId = "rbxassetid://180426354"
local Whiskers = {
    CFrame.Angles(0, math.rad(30), 0),
    CFrame.Angles(0, math.rad(-30), 0),
    CFrame.Angles(0, math.rad(60), 0),
    CFrame.Angles(0, math.rad(-60), 0)
}

local Signal = {}
Signal.__index = Signal
function Signal.new()
    local self = setmetatable({}, Signal)
    self._bindable = Instance.new("BindableEvent")
    return self
end
function Signal:Fire(...)
    self._bindable:Fire(...)
end
function Signal:Wait()
    return self._bindable.Event:Wait()
end
function Signal:Connect(handler)
    return self._bindable.Event:Connect(handler)
end
function Signal:Destroy()
    self._bindable:Destroy()
end

local StateMachine = {}
StateMachine.__index = StateMachine
function StateMachine.new()
    local self = setmetatable({}, StateMachine)
    self.CurrentState = nil
    self.States = {}
    self.OnStateChanged = Signal.new()
    return self
end
function StateMachine:AddState(name, onEnter, onUpdate, onExit)
    self.States[name] = {OnEnter = onEnter, OnUpdate = onUpdate, OnExit = onExit}
end
function StateMachine:SetState(name, ...)
    if self.CurrentState == name then return end
    if self.CurrentState and self.States[self.CurrentState].OnExit then
        self.States[self.CurrentState].OnExit()
    end
    self.CurrentState = name
    if self.States[name].OnEnter then
        self.States[name].OnEnter(...)
    end
    self.OnStateChanged:Fire(name)
end
function StateMachine:Update(dt)
    if self.CurrentState and self.States[self.CurrentState].OnUpdate then
        self.States[self.CurrentState].OnUpdate(dt)
    end
end
function StateMachine:Destroy()
    self.OnStateChanged:Destroy()
    self.States = {}
end

local PlayerCache = {}
PlayerCache.__index = PlayerCache
function PlayerCache.new()
    local self = setmetatable({}, PlayerCache)
    self.Characters = {}
    self.Connections = {}
    return self
end
function PlayerCache:Init()
    for _, player in ipairs(Players:GetPlayers()) do
        self:AddPlayer(player)
    end
    table.insert(self.Connections, Players.PlayerAdded:Connect(function(player)
        self:AddPlayer(player)
    end))
    table.insert(self.Connections, Players.PlayerRemoving:Connect(function(player)
        self:RemovePlayer(player)
    end))
end
function PlayerCache:AddPlayer(player)
    if player.Character then
        self.Characters[player] = player.Character
    end
    local conn = player.CharacterAdded:Connect(function(char)
        self.Characters[player] = char
    end)
    local conn2 = player.CharacterRemoving:Connect(function()
        self.Characters[player] = nil
    end)
    self.Connections[player.Name .. "added"] = conn
    self.Connections[player.Name .. "removing"] = conn2
end
function PlayerCache:RemovePlayer(player)
    self.Characters[player] = nil
    if self.Connections[player.Name .. "added"] then
        self.Connections[player.Name .. "added"]:Disconnect()
        self.Connections[player.Name .. "removing"]:Disconnect()
    end
end
function PlayerCache:GetActiveCharacters()
    local active = {}
    for _, char in pairs(self.Characters) do
        if char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
            table.insert(active, char)
        end
    end
    return active
end
function PlayerCache:Destroy()
    for _, conn in pairs(self.Connections) do
        conn:Disconnect()
    end
    self.Characters = {}
end

local RigController = {}
RigController.__index = RigController
function RigController.new(rigModel, playerCache)
    local self = setmetatable({}, RigController)
    self.Rig = rigModel
    self.Root = rigModel:WaitForChild("HumanoidRootPart", 5)
    self.Humanoid = rigModel:WaitForChild("Humanoid", 5)
    if not self.Root or not self.Humanoid then return nil end
    self.PlayerCache = playerCache
    self.StateMachine = StateMachine.new()
    self.Connections = {}
    self.TargetPosition = self.Root.Position
    self.CurrentVelocity = Vector3.new(0, 0, 0)
    self.HipHeight = self.Humanoid.HipHeight > 0 and self.Humanoid.HipHeight or 2
    self:SetupPhysics()
    self:SetupAnimation()
    self:SetupStates()
    self.StateMachine:SetState("Idle")
    return self
end
function RigController:SetupPhysics()
    self.Attachment = Instance.new("Attachment")
    self.Attachment.Parent = self.Root
    self.AlignPosition = Instance.new("AlignPosition")
    self.AlignPosition.Attachment0 = self.Attachment
    self.AlignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
    self.AlignPosition.MaxForce = 300000
    self.AlignPosition.MaxVelocity = MaxSpeed
    self.AlignPosition.Responsiveness = Responsiveness
    self.AlignPosition.Parent = self.Root
    self.AlignOrientation = Instance.new("AlignOrientation")
    self.AlignOrientation.Attachment0 = self.Attachment
    self.AlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    self.AlignOrientation.MaxTorque = 300000
    self.AlignOrientation.Responsiveness = Responsiveness
    self.AlignOrientation.Parent = self.Root
    self.Humanoid.PlatformStand = true
    for _, part in ipairs(self.Rig:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.5, 1, 1)
            part.Massless = true
            part.CanCollide = false
        end
    end
    self.Root.Massless = false
    self.Root.CanCollide = true
end
function RigController:SetupAnimation()
    local animator = self.Humanoid:FindFirstChild("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = self.Humanoid
    end
    local anim = Instance.new("Animation")
    anim.AnimationId = WalkAnimId
    self.WalkTrack = animator:LoadAnimation(anim)
end
function RigController:GetGroundPosition(targetPos)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {self.Rig}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    local origin = targetPos + RaycastOffset
    local result = Workspace:Raycast(origin, RaycastDirection, raycastParams)
    if result then
        return result.Position + Vector3.new(0, self.HipHeight + (self.Root.Size.Y / 2), 0), result.Normal
    end
    return targetPos, Vector3.new(0, 1, 0)
end
function RigController:CalculateAvoidance(origin, direction)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {self.Rig}
    for _, char in ipairs(self.PlayerCache:GetActiveCharacters()) do
        table.insert(raycastParams.FilterDescendantsInstances, char)
    end
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    local mainResult = Workspace:Raycast(origin, direction * 8, raycastParams)
    if not mainResult then return direction end
    local bestDirection = direction
    local maxDistance = 0
    for _, whisker in ipairs(Whiskers) do
        local testDirection = whisker * direction
        local result = Workspace:Raycast(origin, testDirection * 8, raycastParams)
        if not result then
            return testDirection
        else
            local dist = (result.Position - origin).Magnitude
            if dist > maxDistance then
                maxDistance = dist
                bestDirection = testDirection
            end
        end
    end
    return bestDirection
end
function RigController:SetupStates()
    self.StateMachine:AddState("Idle",
        function()
            if self.WalkTrack and self.WalkTrack.IsPlaying then
                self.WalkTrack:Stop(0.2)
            end
        end,
        function(dt)
            self.CurrentVelocity = self.CurrentVelocity:Lerp(Vector3.new(0, 0, 0), dt * Acceleration)
            self.AlignPosition.MaxVelocity = math.max(self.CurrentVelocity.Magnitude, 1)
            local threat, dist = self:FindNearestThreat()
            if threat and dist < FleeDistance then
                self.StateMachine:SetState("Flee", threat)
            end
            local groundPos, groundNormal = self:GetGroundPosition(self.Root.Position)
            self.AlignPosition.Position = groundPos
            local rightVector = self.Root.CFrame.RightVector
            local forwardVector = groundNormal:Cross(rightVector).Unit
            rightVector = forwardVector:Cross(groundNormal).Unit
            self.AlignOrientation.CFrame = CFrame.fromMatrix(self.Root.Position, rightVector, groundNormal, -forwardVector)
        end,
        function()
            self.AlignPosition.MaxVelocity = MaxSpeed
        end
    )
    self.StateMachine:AddState("Flee",
        function(threat)
            self.CurrentThreat = threat
            if self.WalkTrack and not self.WalkTrack.IsPlaying then
                self.WalkTrack:Play(0.1)
            end
        end,
        function(dt)
            local threat, dist = self:FindNearestThreat()
            if not threat or dist >= StopFleeDistance then
                self.StateMachine:SetState("Idle")
                return
            end
            local myPos = self.Root.Position
            local threatPos = threat.HumanoidRootPart.Position
            local rawDirection = (myPos - threatPos).Unit
            if rawDirection ~= rawDirection then rawDirection = Vector3.new(1, 0, 0) end
            local flatDirection = Vector3.new(rawDirection.X, 0, rawDirection.Z).Unit
            local avoidDirection = self:CalculateAvoidance(myPos, flatDirection)
            self.CurrentVelocity = self.CurrentVelocity:Lerp(avoidDirection * MaxSpeed, dt * Acceleration)
            local currentMag = self.CurrentVelocity.Magnitude
            if self.WalkTrack then
                self.WalkTrack:AdjustSpeed(math.clamp(currentMag / 16, 0.1, 1.2))
            end
            local targetPos = myPos + (self.CurrentVelocity * dt)
            local groundPos, groundNormal = self:GetGroundPosition(targetPos)
            self.TargetPosition = groundPos
            self.AlignPosition.Position = self.TargetPosition
            local lookDirection = -avoidDirection
            local rightVector = lookDirection:Cross(groundNormal).Unit
            local forwardVector = groundNormal:Cross(rightVector).Unit
            self.AlignOrientation.CFrame = CFrame.fromMatrix(myPos, rightVector, groundNormal, -forwardVector)
        end,
        function()
            self.CurrentThreat = nil
        end
    )
end
function RigController:FindNearestThreat()
    local chars = self.PlayerCache:GetActiveCharacters()
    local nearest = nil
    local minDist = math.huge
    local myPos = self.Root.Position
    for _, char in ipairs(chars) do
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local dist = (hrp.Position - myPos).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = char
            end
        end
    end
    return nearest, minDist
end
function RigController:Start()
    local conn = RunService.Heartbeat:Connect(function(dt)
        self.StateMachine:Update(dt)
    end)
    table.insert(self.Connections, conn)
end
function RigController:Destroy()
    for _, conn in ipairs(self.Connections) do
        conn:Disconnect()
    end
    if self.WalkTrack then
        self.WalkTrack:Stop()
        self.WalkTrack:Destroy()
    end
    self.AlignPosition:Destroy()
    self.AlignOrientation:Destroy()
    self.Attachment:Destroy()
    self.StateMachine:Destroy()
    self.Humanoid.PlatformStand = false
    for _, part in ipairs(self.Rig:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Massless = false
            part.CanCollide = true
            part.CustomPhysicalProperties = nil
        end
    end
end

local RigManager = {}
RigManager.__index = RigManager
function RigManager.new()
    local self = setmetatable({}, RigManager)
    self.Controllers = {}
    self.PlayerCache = PlayerCache.new()
    self.PlayerCache:Init()
    self.Connection = nil
    return self
end
function RigManager:RegisterRig(rigModel)
    if not rigModel:IsA("Model") then return end
    if self.Controllers[rigModel] then return end
    local controller = RigController.new(rigModel, self.PlayerCache)
    if controller then
        controller:Start()
        self.Controllers[rigModel] = controller
    end
end
function RigManager:UnregisterRig(rigModel)
    if self.Controllers[rigModel] then
        self.Controllers[rigModel]:Destroy()
        self.Controllers[rigModel] = nil
    end
end
function RigManager:AutoDiscover()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name == TargetRigName and obj:FindFirstChild("Humanoid") then
            self:RegisterRig(obj)
        end
    end
    self.Connection = Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Model") and obj.Name == TargetRigName then
            task.delay(0.1, function()
                if obj:FindFirstChild("Humanoid") then
                    self:RegisterRig(obj)
                end
            end)
        end
    end)
    Workspace.DescendantRemoving:Connect(function(obj)
        if obj:IsA("Model") and self.Controllers[obj] then
            self:UnregisterRig(obj)
        end
    end)
end
function RigManager:Destroy()
    self.PlayerCache:Destroy()
    if self.Connection then
        self.Connection:Disconnect()
    end
    for rig, controller in pairs(self.Controllers) do
        controller:Destroy()
    end
    self.Controllers = {}
end

local managerInstance = RigManager.new()
managerInstance:AutoDiscover()
