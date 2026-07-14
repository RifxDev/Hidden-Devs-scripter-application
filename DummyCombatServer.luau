local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local config = require(ReplicatedStorage:WaitForChild("DummyCombatConfig"))
local questConfig = require(ReplicatedStorage:WaitForChild("DummyQuestConfig"))

local dummyDefeatedEvent = ReplicatedStorage:FindFirstChild(questConfig.DummyDefeatedBindableName)
if not dummyDefeatedEvent then
	dummyDefeatedEvent = Instance.new("BindableEvent")
	dummyDefeatedEvent.Name = questConfig.DummyDefeatedBindableName
	dummyDefeatedEvent.Parent = ReplicatedStorage
end

local remoteEvent = ReplicatedStorage:FindFirstChild(config.RemoteEventName)
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = config.RemoteEventName
	remoteEvent.Parent = ReplicatedStorage
end

local firstDummy = Workspace:WaitForChild(config.DummyName)
firstDummy.Archivable = true

local spawnParent = firstDummy.Parent
local spawnPivot = firstDummy:GetPivot()
local dummyTemplate = firstDummy:Clone()

local dummy = nil
local dummyHumanoid = nil
local dummyRoot = nil
local dummyHead = nil
local healthText = nil
local healthFill = nil
local healthConnection = nil
local diedConnection = nil
local knockbackTrack = nil
local lastDamageTime = -math.huge
local lastHealth = 100
local lastAttackTimes = {}
local isDead = false
local lastDamagePlayer = nil
local killDummy = nil

local function setServerPhysics(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = false
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end
end

local function createHealthGui()
	local oldGui = dummy:FindFirstChild("DummyHealthGui")
	if oldGui then
		oldGui:Destroy()
	end

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "DummyHealthGui"
	billboardGui.Adornee = dummyHead
	billboardGui.AlwaysOnTop = true
	billboardGui.MaxDistance = 1000
	billboardGui.Size = UDim2.fromOffset(150, 38)
	billboardGui.StudsOffset = Vector3.new(0, 2.45, 0)
	billboardGui.Parent = dummy

	local label = Instance.new("TextLabel")
	label.Name = "HealthText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Font = Enum.Font.Code
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = billboardGui

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	barBack.BorderSizePixel = 0
	barBack.Position = UDim2.fromOffset(18, 24)
	barBack.Size = UDim2.new(1, -36, 0, 9)
	barBack.Parent = billboardGui

	local barBackCorner = Instance.new("UICorner")
	barBackCorner.CornerRadius = UDim.new(0, 0)
	barBackCorner.Parent = barBack

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.BackgroundColor3 = Color3.fromRGB(63, 230, 105)
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.Parent = barBack

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0, 0)
	barFillCorner.Parent = barFill

	return label, barFill
end

local function updateHealthGui()
	if not healthText or not healthFill or not dummyHumanoid then
		return
	end

	local health = math.max(0, math.floor(dummyHumanoid.Health + 0.5))
	local maxHealth = math.max(1, math.floor(dummyHumanoid.MaxHealth + 0.5))
	local ratio = math.clamp(health / maxHealth, 0, 1)

	healthText.Text = string.format("%d/%d HP", health, maxHealth)
	healthFill.Size = UDim2.fromScale(ratio, 1)

	if ratio > 0.55 then
		healthFill.BackgroundColor3 = Color3.fromRGB(63, 230, 105)
	elseif ratio > 0.25 then
		healthFill.BackgroundColor3 = Color3.fromRGB(255, 205, 78)
	else
		healthFill.BackgroundColor3 = Color3.fromRGB(255, 76, 76)
	end
end

local function getPlayerRoot(player)
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function isDummyInHitBox(playerRoot)
	if not dummyRoot then
		return false
	end

	local localPosition = playerRoot.CFrame:PointToObjectSpace(dummyRoot.Position)
	local inFront = localPosition.Z <= 1 and localPosition.Z >= -config.HitRange
	local inWidth = math.abs(localPosition.X) <= config.HitHalfWidth
	local inHeight = math.abs(localPosition.Y) <= config.HitHalfHeight
	return inFront and inWidth and inHeight
end

local function playKnockbackAnimation()
	if not dummyHumanoid or not config.KnockbackAnimationId then
		return
	end

	local animator = dummyHumanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = dummyHumanoid
	end

	if knockbackTrack then
		knockbackTrack:Stop(0)
		knockbackTrack:Destroy()
		knockbackTrack = nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = config.KnockbackAnimationId

	local loaded, trackOrError = pcall(function()
		return dummyHumanoid:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not loaded then
		warn("Dummy knockback animation failed to load: " .. tostring(trackOrError))
		return
	end

	knockbackTrack = trackOrError
	knockbackTrack.Priority = Enum.AnimationPriority.Action4
	knockbackTrack.Looped = false
	knockbackTrack:Play(0.02, 1, 1)
	knockbackTrack:AdjustSpeed(1)

	local currentTrack = knockbackTrack
	task.delay(config.KnockbackAnimationDuration, function()
		if knockbackTrack == currentTrack and currentTrack.IsPlaying then
			currentTrack:Stop(0.04)
		end
	end)
end

local function applyKnockback(playerRoot, combo)
	if not dummyRoot then
		return
	end

	local direction = dummyRoot.Position - playerRoot.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.05 then
		direction = Vector3.new(playerRoot.CFrame.LookVector.X, 0, playerRoot.CFrame.LookVector.Z)
	end

	if direction.Magnitude < 0.05 then
		return
	end

	local multiplier = combo.KnockbackMultiplier or 1
	local horizontalVelocity = direction.Unit * config.KnockbackForce * multiplier
	dummyRoot.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, config.KnockbackUpForce * multiplier, horizontalVelocity.Z)
end

-- ragdoll

local function ragdollDummy()
	if not dummy or not dummyHumanoid then
		return
	end

	dummyHumanoid.PlatformStand = true
	dummyHumanoid.AutoRotate = false
	dummyHumanoid:ChangeState(Enum.HumanoidStateType.Physics)

	for _, descendant in ipairs(dummy:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			local attachment0 = Instance.new("Attachment")
			attachment0.Name = "RagdollAttachment0"
			attachment0.CFrame = descendant.C0
			attachment0.Parent = descendant.Part0

			local attachment1 = Instance.new("Attachment")
			attachment1.Name = "RagdollAttachment1"
			attachment1.CFrame = descendant.C1
			attachment1.Parent = descendant.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = 60
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Parent = descendant.Parent

			descendant.Enabled = false
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = descendant.Name ~= "HumanoidRootPart"
		end
	end
end

local function setupDummy(model)
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	if diedConnection then
		diedConnection:Disconnect()
		diedConnection = nil
	end

	dummy = model
	dummyHumanoid = dummy:WaitForChild("Humanoid")
	dummyRoot = dummy:WaitForChild("HumanoidRootPart")
	dummyHead = dummy:FindFirstChild("Head") or dummyRoot
	isDead = false
	knockbackTrack = nil
	lastDamagePlayer = nil
	lastDamageTime = -math.huge

	dummyHumanoid.BreakJointsOnDeath = false
	dummyHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	dummyHumanoid.PlatformStand = false
	dummyHumanoid.AutoRotate = true
	setServerPhysics(dummy)

	healthText, healthFill = createHealthGui()
	lastHealth = dummyHumanoid.Health
	updateHealthGui()

	healthConnection = dummyHumanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealth then
			lastDamageTime = os.clock()
		end

		lastHealth = newHealth
		updateHealthGui()

		if newHealth <= 0 and killDummy then
			killDummy(lastDamagePlayer)
		end
	end)

	diedConnection = dummyHumanoid.Died:Connect(function()
		if killDummy then
			killDummy(lastDamagePlayer)
		end
	end)
end

local function respawnDummy()
	if dummy and dummy.Parent then
		dummy:Destroy()
	end

	local newDummy = dummyTemplate:Clone()
	newDummy.Name = config.DummyName
	newDummy.Parent = spawnParent
	newDummy:PivotTo(spawnPivot)
	setupDummy(newDummy)
end

killDummy = function(defeatedBy)
	if isDead then
		return
	end

	isDead = true
	updateHealthGui()
	if defeatedBy and defeatedBy.Parent == Players then
		dummyDefeatedEvent:Fire(defeatedBy)
	end
	ragdollDummy()

	task.delay(config.RespawnDelay, function()
		respawnDummy()
	end)
end

local function damageDummy(player, comboIndex)
	if isDead then
		return
	end

	local combo = config.Combos[comboIndex]
	if not combo then
		return
	end

	local playerRoot = getPlayerRoot(player)
	if not playerRoot or not isDummyInHitBox(playerRoot) then
		return
	end

	local detectedPlayerRoot = playerRoot
	task.delay(config.HitReactionDelay, function()
		if isDead or not dummyHumanoid or not dummyRoot or not detectedPlayerRoot.Parent then
			return
		end

		lastDamageTime = os.clock()
		lastDamagePlayer = player
		local newHealth = math.max(0, dummyHumanoid.Health - combo.Damage)
		applyKnockback(detectedPlayerRoot, combo)

		if newHealth > 0 then
			playKnockbackAnimation()
		end

		dummyHumanoid.Health = newHealth
		lastHealth = dummyHumanoid.Health
		updateHealthGui()

		if dummyHumanoid.Health <= 0 then
			killDummy(player)
		end
	end)
end

remoteEvent.OnServerEvent:Connect(function(player, comboIndex)
	if typeof(comboIndex) ~= "number" then
		return
	end

	comboIndex = math.floor(comboIndex)
	local combo = config.Combos[comboIndex]
	if not combo then
		return
	end

	local now = os.clock()
	local lastAttackTime = lastAttackTimes[player] or -math.huge
	if now - lastAttackTime < config.ServerMinAttackGap then
		return
	end

	lastAttackTimes[player] = now
	task.delay(combo.ImpactDelay, function()
		if player.Parent == Players then
			damageDummy(player, comboIndex)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastAttackTimes[player] = nil
end)

setupDummy(firstDummy)

task.spawn(function()
	while true do
		task.wait(0.5)

		if dummyHumanoid and not isDead and dummyHumanoid.Health < dummyHumanoid.MaxHealth and os.clock() - lastDamageTime >= config.RegenerationDelay then
			dummyHumanoid.Health = math.min(dummyHumanoid.MaxHealth, dummyHumanoid.Health + config.RegenerationPerSecond * 0.5)
			lastHealth = dummyHumanoid.Health
			updateHealthGui()
		end
	end
end)