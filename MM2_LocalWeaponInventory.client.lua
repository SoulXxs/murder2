--// MM2 Local Weapon Inventory / Grant Controller
--// ONE LocalScript
--// Put in: StarterPlayer > StarterPlayerScripts
--//
--// This script uses the data that already exists in the place:
--//   ReplicatedStorage.Database.Sync.Weapons
--//   ReplicatedStorage.Modules.ProfileData
--//   ReplicatedStorage.Remotes.Inventory.InventoryDataChanged--// MM2 Local Weapon Inventory / Grant Controller
--// ONE LocalScript
--// Put in: StarterPlayer > StarterPlayerScripts
--//
--// This script uses the data that already exists in the place:
--//   ReplicatedStorage.Database.Sync.Weapons
--//   ReplicatedStorage.Modules.ProfileData
--//   ReplicatedStorage.Remotes.Inventory.InventoryDataChanged
--//
--// No permission check and no RemoteEvent request are used for the grant.
--// Clicking GIVE adds the item to the LOCAL player's inventory only.
--// There is intentionally NO EQUIP button here.
--// After granting, use the game's normal Inventory UI to equip the item.
--//
--// IMPORTANT:
--// The supplied place stores the real weapon Tool templates under ServerStorage.
--// A LocalScript cannot read ServerStorage. Therefore the Equip function first
--// looks for a client-visible Tool template (ReplicatedStorage / StarterPack).
--// If none exists, it creates a local Tool with the real weapon icon/name as a
--// safe fallback. Move/copy the real visual Tool templates to ReplicatedStorage
--// if you want the exact 3D weapon model locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Sync = require(
	ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync")
)

local ProfileData = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData")
)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InventoryRemotes = Remotes:WaitForChild("Inventory")
local InventoryDataChanged = InventoryRemotes:FindFirstChild("InventoryDataChanged")

local Weapons = Sync.Weapons or Sync.Item or {}

local ownedLocal = {}
local currentTool = nil
local currentWeaponId = nil

-- ============================================================
-- Helpers
-- ============================================================

local function getWeaponInfo(itemId)
	return Weapons[itemId]
end

local function getWeaponDisplayName(itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return tostring(itemId)
	end

	return info.ItemName or info.Name or info.DisplayName or itemId
end

local function getWeaponImage(itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return ""
	end

	local image = info.Image or info.Icon
	if not image then
		return ""
	end

	if tonumber(image) then
		return "rbxthumb://type=Asset&w=150&h=150&id=" .. tostring(image)
	end

	return tostring(image)
end

local currentVisual = nil

local function getCharacter()
	return LocalPlayer.Character
end

local function findRightHand(character)
	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("RightUpperArm")
end

local function findLeftShoulder(character)
	return character:FindFirstChild("LeftUpperArm")
		or character:FindFirstChild("Left Arm")
		or character:FindFirstChild("LeftHand")
end

local function destroyLocalVisual()
	if currentVisual and currentVisual.Parent then
		currentVisual:Destroy()
	end
	currentVisual = nil
end

local function removeLocalWeapon()
	if currentTool then
		currentTool:Destroy()
		currentTool = nil
	end

	if currentVisual then
		destroyLocalVisual()
	end

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, object in ipairs(backpack:GetChildren()) do
			if object:IsA("Tool") and object:GetAttribute("MM2LocalWeapon") == true then
				object:Destroy()
			end
		end
	end

	local character = LocalPlayer.Character
	if character then
		for _, object in ipairs(character:GetChildren()) do
			if object:IsA("Tool") and object:GetAttribute("MM2LocalWeapon") == true then
				object:Destroy()
			end
		end
	end
end

local function findClientToolTemplate(itemId)
	-- Exact item model, if the place exposes it to the client.
	local containers = { ReplicatedStorage, StarterPack }

	for _, root in ipairs(containers) do
		local exact = root:FindFirstChild(itemId, true)
		if exact and exact:IsA("Tool") then
			return exact
		end
	end

	-- Tool identified by ItemID / OriginalItemID.
	for _, root in ipairs(containers) do
		for _, object in ipairs(root:GetDescendants()) do
			if object:IsA("Tool") then
				if object:GetAttribute("ItemID") == itemId
					or object:GetAttribute("OriginalItemID") == itemId then
					return object
				end
			end
		end
	end

	return nil
end

local function findGenericVisibleTool(itemId)
	-- If the exact item is server-only, use a client-visible Knife/Gun model
	-- as a 3D base. The item's own texture/icon is then applied to it.
	local wanted = string.lower(itemId)
	local isGun = string.find(wanted, "gun", 1, true) ~= nil
		or string.find(wanted, "luger", 1, true) ~= nil
		or string.find(wanted, "blaster", 1, true) ~= nil
		or string.find(wanted, "pistol", 1, true) ~= nil
		or string.find(wanted, "revolver", 1, true) ~= nil

	local names = isGun and { "Gun", "DefaultGun" } or { "Knife", "DefaultKnife" }
	local roots = { ReplicatedStorage, StarterPack }

	-- Prefer a model already visible on the local character/backpack.
	local character = LocalPlayer.Character
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	local localRoots = { character, backpack }
	for _, root in ipairs(localRoots) do
		if root then
			for _, object in ipairs(root:GetChildren()) do
				if object:IsA("Tool") then
					for _, name in ipairs(names) do
						if string.lower(object.Name) == string.lower(name) then
							return object
						end
					end
				end
			end
		end
	end

	for _, root in ipairs(roots) do
		for _, name in ipairs(names) do
			local found = root:FindFirstChild(name, true)
			if found and found:IsA("Tool") then
				return found
			end
		end
	end

	return nil
end

local function applyWeaponTexture(instance, itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return
	end

	local image = info.Image or info.Icon
	if not image then
		return
	end

	local imageId = tostring(image)
	if imageId:match("^%d+$") then
		imageId = "rbxassetid://" .. imageId
	end

	for _, object in ipairs(instance:GetDescendants()) do
		if object:IsA("Decal") or object:IsA("Texture") then
			object.Texture = imageId
		elseif object:IsA("MeshPart") then
			-- Keep the actual mesh/material of the client-visible base.
			-- TextureId is read-only on some MeshPart setups, so don't force it.
		end
	end

	local tool = instance:IsA("Tool") and instance or instance:FindFirstChildWhichIsA("Tool", true)
	if tool then
		pcall(function()
			tool.TextureId = imageId
		end)
	end
end

local function weldModelToPart(model, targetPart, offset)
	if not model or not targetPart then
		return false
	end

	local primary = model.PrimaryPart
	if not primary then
		primary = model:FindFirstChild("Handle", true)
	end
	if not primary or not primary:IsA("BasePart") then
		primary = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not primary then
		return false
	end

	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Anchored = false
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Massless = true
		end
	end

	model.PrimaryPart = primary
	model:PivotTo(targetPart.CFrame * offset)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "MM2LocalVisualWeld"
	weld.Part0 = primary
	weld.Part1 = targetPart
	weld.Parent = primary

	return true
end

local function makeFallbackVisual(itemId)
	local baseTool = findGenericVisibleTool(itemId)
	if not baseTool then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "MM2LocalVisual_" .. tostring(itemId)
	model:SetAttribute("MM2LocalWeapon", true)
	model:SetAttribute("ItemID", itemId)
	model:SetAttribute("OriginalItemID", itemId)

	for _, child in ipairs(baseTool:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
			local clone = child:Clone()
			clone.Parent = model
		end
	end

	applyWeaponTexture(model, itemId)
	return model
end

local function makeFallbackTool(itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = getWeaponDisplayName(itemId)
	tool.ToolTip = getWeaponDisplayName(itemId)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("MM2LocalWeapon", true)
	tool:SetAttribute("ItemID", itemId)
	tool:SetAttribute("OriginalItemID", itemId)

	local image = info.Image or info.Icon
	if image then
		tool.TextureId = tostring(image):match("^%d+$")
			and "rbxassetid://" .. tostring(image)
			or tostring(image)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.25, 1.5, 0.12)
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Transparency = 1
	handle.Parent = tool

	return tool
end

local function attachExactToolVisual(tool, itemId)
	local character = getCharacter()
	local hand = findRightHand(character)
	if not character or not hand then
		return false
	end

	-- Clone the Tool's visible parts into a separate Model. This lets us keep
	-- the visual attached to the hand even if Roblox's Tool grip is changed.
	local model = Instance.new("Model")
	model.Name = "MM2LocalVisual_" .. tostring(itemId)
	model:SetAttribute("MM2LocalWeapon", true)
	model:SetAttribute("ItemID", itemId)
	model:SetAttribute("OriginalItemID", itemId)

	for _, child in ipairs(tool:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
			local clone = child:Clone()
			clone.Parent = model
		end
	end

	if not weldModelToPart(model, hand, CFrame.new(0, -0.25, -0.35) * CFrame.Angles(math.rad(-90), 0, 0)) then
		model:Destroy()
		return false
	end

	model.Parent = character
	currentVisual = model
	return true
end

local function createLocalEquippedTool(itemId)
	if not Weapons[itemId] then
		return false
	end

	-- Called ONLY when the game's normal MM2 inventory equips a weapon.
	removeLocalWeapon()

	local template = findClientToolTemplate(itemId)
	local base = template or findGenericVisibleTool(itemId)
	if not base then
		warn("[MM2Local] No client-visible Tool template for", itemId)
		return false
	end

	local tool = base:Clone()
	tool:SetAttribute("MM2LocalWeapon", true)
	tool:SetAttribute("ItemID", itemId)
	tool:SetAttribute("OriginalItemID", itemId)
	tool.Name = template and getWeaponDisplayName(itemId)
		or (string.find(string.lower(itemId), "gun", 1, true) and "Gun" or "Knife")
	tool.CanBeDropped = false

	-- Use the client-visible Tool itself. If it contains the game's LocalScripts,
	-- they remain inside the clone, so normal activation/shooting can work.
	local backpack = LocalPlayer:WaitForChild("Backpack")
	tool.Parent = backpack
	currentTool = tool
	currentWeaponId = itemId

	applyWeaponTexture(tool, itemId)

	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end

	-- Fallback visual: if the Tool's own Handle is not rendered by the local
	-- client, clone its visible parts and weld them directly to the right hand.
	task.defer(function()
		if not currentVisual and tool.Parent then
			local hand = getCharacter() and findRightHand(getCharacter())
			if hand then
				local visual = Instance.new("Model")
				visual.Name = "MM2LocalVisual_" .. tostring(itemId)
				visual:SetAttribute("MM2LocalWeapon", true)
				visual:SetAttribute("ItemID", itemId)
				visual:SetAttribute("OriginalItemID", itemId)

				for _, child in ipairs(tool:GetChildren()) do
					if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
						child:Clone().Parent = visual
					end
				end

				if weldModelToPart(
					visual,
					hand,
					CFrame.new(0, -0.25, -0.35) * CFrame.Angles(math.rad(-90), 0, 0)
				) then
					visual.Parent = getCharacter()
					currentVisual = visual
				else
					visual:Destroy()
				end
			end
		end
	end)

	return true
end

-- ============================================================
-- Hook the game's NORMAL Inventory -> EquipService.
-- There is no custom EQUIP button. When the player presses Equip in the
-- existing MM2 inventory, EquipService fires EquippedChanged locally.
-- We react to that event and create the local Tool.
-- ============================================================

local function connectEquipService()
	local modulesRoot = ReplicatedStorage:FindFirstChild("Modules")
	if not modulesRoot then
		return false
	end

	local equipModule = modulesRoot:FindFirstChild("EquipService", true)
	if not equipModule or not equipModule:IsA("ModuleScript") then
		return false
	end

	local ok, EquipService = pcall(require, equipModule)
	if not ok or not EquipService then
		warn("[MM2Local] Could not require EquipService:", EquipService)
		return false
	end

	local changed = EquipService.EquippedChanged
	if not changed then
		return false
	end

	if typeof(changed) == "Instance" and changed:IsA("BindableEvent") then
		changed.Event:Connect(function(itemType, itemId)
			if (itemType == "Knife" or itemType == "Gun" or itemType == "Weapons") and type(itemId) == "string" then
				task.defer(function()
					createLocalEquippedTool(itemId)
				end)
			end
		end)
		return true
	end

	-- GoodSignal/Signal-style object.
	local connect = changed.Connect
	if type(connect) == "function" then
		connect(changed, function(itemType, itemId)
			if (itemType == "Knife" or itemType == "Gun" or itemType == "Weapons") and type(itemId) == "string" then
				task.defer(function()
					createLocalEquippedTool(itemId)
				end)
			end
		end)
		return true
	end

	return false
end

if not connectEquipService() then
	warn("[MM2Local] EquipService hook was not found. The normal inventory can still grant items, but local Tool creation on normal Equip is unavailable.")
end

LocalPlayer.CharacterAdded:Connect(function()
	task.defer(function()
		local weaponsData = ProfileData.Weapons
		local equipped = weaponsData and weaponsData.Equipped
		local itemId = equipped and (equipped.Knife or equipped.Gun)

		if type(itemId) == "string" and Weapons[itemId]
			and (ownedLocal[itemId] or (weaponsData.Owned and weaponsData.Owned[itemId])) then
			task.wait(0.5)
			createLocalEquippedTool(itemId)
		end
	end)
end)

-- ============================================================
-- Local inventory grant
-- ============================================================

local function addLocalItem(itemId)
	if not Weapons[itemId] then
		return false
	end

	ownedLocal[itemId] = true

	-- The place's ProfileData uses Weapons.Owned[itemId].
	-- This changes only the local copy of ProfileData.
	ProfileData.Weapons = ProfileData.Weapons or {}
	ProfileData.Weapons.Owned = ProfileData.Weapons.Owned or {}
	ProfileData.Weapons.Owned[itemId] = 1

	-- Tell the existing client inventory UI about the local item.
	-- InventoryDataChanged is a BindableEvent in the supplied place.
	if InventoryDataChanged and InventoryDataChanged:IsA("BindableEvent") then
		InventoryDataChanged:Fire("Weapons", itemId, 1)
	end

	return true
end

-- ============================================================
-- GUI
-- ============================================================

local oldGui = PlayerGui:FindFirstChild("MM2LocalWeaponController")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MM2LocalWeaponController"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

local openButton = Instance.new("TextButton")
openButton.Name = "Open"
openButton.Size = UDim2.fromOffset(150, 38)
openButton.Position = UDim2.new(0, 15, 1, -55)
openButton.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 15
openButton.Font = Enum.Font.GothamBold
openButton.Text = "LOCAL WEAPONS"
openButton.Parent = gui

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 8)
openCorner.Parent = openButton

local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(430, 520)
window.Position = UDim2.new(0.5, -215, 0.5, -260)
window.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
window.BorderSizePixel = 0
window.Visible = false
window.Parent = gui

local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 10)
windowCorner.Parent = window

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(65, 65, 72)
stroke.Parent = window

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 42)
title.Position = UDim2.fromOffset(15, 5)
title.BackgroundTransparency = 1
title.Text = "MM2 Local Weapon Inventory"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = window

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(35, 35)
close.Position = UDim2.new(1, -42, 0, 7)
close.BackgroundTransparency = 1
close.Text = "×"
close.TextColor3 = Color3.fromRGB(255, 255, 255)
close.TextSize = 25
close.Font = Enum.Font.GothamBold
close.Parent = window

local search = Instance.new("TextBox")
search.Size = UDim2.new(1, -30, 0, 38)
search.Position = UDim2.fromOffset(15, 50)
search.BackgroundColor3 = Color3.fromRGB(35, 35, 41)
search.BorderSizePixel = 0
search.PlaceholderText = "Search weapon..."
search.PlaceholderColor3 = Color3.fromRGB(150, 150, 155)
search.TextColor3 = Color3.fromRGB(255, 255, 255)
search.TextSize = 14
search.Font = Enum.Font.Gotham
search.ClearTextOnFocus = false
search.Parent = window

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 7)
searchCorner.Parent = search

local list = Instance.new("ScrollingFrame")
list.Name = "WeaponList"
list.Size = UDim2.new(1, -30, 1, -105)
list.Position = UDim2.fromOffset(15, 95)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = window

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function makeWeaponRow(itemId, info, order)
	local row = Instance.new("Frame")
	row.Name = itemId
	row.Size = UDim2.new(1, -5, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = list

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(48, 48)
	icon.Position = UDim2.fromOffset(5, 5)
	icon.BackgroundTransparency = 1
	icon.Image = getWeaponImage(itemId)
	icon.Parent = row

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -190, 1, 0)
	name.Position = UDim2.fromOffset(62, 0)
	name.BackgroundTransparency = 1
	name.Text = getWeaponDisplayName(itemId)
	name.TextColor3 = Color3.fromRGB(240, 240, 240)
	name.TextSize = 14
	name.Font = Enum.Font.GothamMedium
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = row

	local give = Instance.new("TextButton")
	give.Size = UDim2.fromOffset(58, 32)
	give.Position = UDim2.new(1, -125, 0.5, -16)
	give.BackgroundColor3 = Color3.fromRGB(55, 55, 63)
	give.Text = ownedLocal[itemId] and "OWNED" or "GIVE"
	give.TextColor3 = Color3.fromRGB(255, 255, 255)
	give.TextSize = 11
	give.Font = Enum.Font.GothamBold
	give.Parent = row

	local giveCorner = Instance.new("UICorner")
	giveCorner.CornerRadius = UDim.new(0, 6)
	giveCorner.Parent = give

	give.Activated:Connect(function()
		if addLocalItem(itemId) then
			give.Text = "OWNED"
		end
	end)

	return row
end

-- Sort by display name, while preserving every real item ID from Sync.Weapons.
local itemIds = {}
for itemId, info in pairs(Weapons) do
	if type(itemId) == "string" and type(info) == "table" then
		table.insert(itemIds, itemId)
	end
end

table.sort(itemIds, function(a, b)
	return string.lower(getWeaponDisplayName(a)) < string.lower(getWeaponDisplayName(b))
end)

local rows = {}
for order, itemId in ipairs(itemIds) do
	rows[itemId] = makeWeaponRow(itemId, Weapons[itemId], order)
end

local function applySearch()
	local query = string.lower(search.Text or "")

	for itemId, row in pairs(rows) do
		local name = string.lower(getWeaponDisplayName(itemId))
		local id = string.lower(itemId)
		row.Visible = query == "" or string.find(name, query, 1, true) ~= nil or string.find(id, query, 1, true) ~= nil
	end
end

search:GetPropertyChangedSignal("Text"):Connect(applySearch)

openButton.Activated:Connect(function()
	window.Visible = not window.Visible
end)

close.Activated:Connect(function()
	window.Visible = false
end)

print("[MM2Local] Loaded. Weapons available:", #itemIds)

--//
--// No permission check and no RemoteEvent request are used for the grant.
--// Clicking GIVE adds the item to the LOCAL player's inventory only.
--// There is intentionally NO EQUIP button here.
--// After granting, use the game's normal Inventory UI to equip the item.
--//
--// IMPORTANT:
--// The supplied place stores the real weapon Tool templates under ServerStorage.
--// A LocalScript cannot read ServerStorage. Therefore the Equip function first
--// looks for a client-visible Tool template (ReplicatedStorage / StarterPack).
--// If none exists, it creates a local Tool with the real weapon icon/name as a
--// safe fallback. Move/copy the real visual Tool templates to ReplicatedStorage
--// if you want the exact 3D weapon model locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Sync = require(
	ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync")
)

local ProfileData = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData")
)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InventoryRemotes = Remotes:WaitForChild("Inventory")
local InventoryDataChanged = InventoryRemotes:FindFirstChild("InventoryDataChanged")

local Weapons = Sync.Weapons or Sync.Item or {}

local ownedLocal = {}
local currentTool = nil
local currentWeaponId = nil

-- ============================================================
-- Helpers
-- ============================================================

local function getWeaponInfo(itemId)
	return Weapons[itemId]
end

local function getWeaponDisplayName(itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return tostring(itemId)
	end

	return info.ItemName or info.Name or info.DisplayName or itemId
end

local function getWeaponImage(itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return ""
	end

	local image = info.Image or info.Icon
	if not image then
		return ""
	end

	if tonumber(image) then
		return "rbxthumb://type=Asset&w=150&h=150&id=" .. tostring(image)
	end

	return tostring(image)
end

local currentVisual = nil

local function getCharacter()
	return LocalPlayer.Character
end

local function findRightHand(character)
	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("RightUpperArm")
end

local function findLeftShoulder(character)
	return character:FindFirstChild("LeftUpperArm")
		or character:FindFirstChild("Left Arm")
		or character:FindFirstChild("LeftHand")
end

local function destroyLocalVisual()
	if currentVisual and currentVisual.Parent then
		currentVisual:Destroy()
	end
	currentVisual = nil
end

local function removeLocalWeapon()
	if currentTool then
		currentTool:Destroy()
		currentTool = nil
	end

	if currentVisual then
		destroyLocalVisual()
	end

	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, object in ipairs(backpack:GetChildren()) do
			if object:IsA("Tool") and object:GetAttribute("MM2LocalWeapon") == true then
				object:Destroy()
			end
		end
	end

	local character = LocalPlayer.Character
	if character then
		for _, object in ipairs(character:GetChildren()) do
			if object:IsA("Tool") and object:GetAttribute("MM2LocalWeapon") == true then
				object:Destroy()
			end
		end
	end
end

local function findClientToolTemplate(itemId)
	-- Exact item model, if the place exposes it to the client.
	local containers = { ReplicatedStorage, StarterPack }

	for _, root in ipairs(containers) do
		local exact = root:FindFirstChild(itemId, true)
		if exact and exact:IsA("Tool") then
			return exact
		end
	end

	-- Tool identified by ItemID / OriginalItemID.
	for _, root in ipairs(containers) do
		for _, object in ipairs(root:GetDescendants()) do
			if object:IsA("Tool") then
				if object:GetAttribute("ItemID") == itemId
					or object:GetAttribute("OriginalItemID") == itemId then
					return object
				end
			end
		end
	end

	return nil
end

local function findGenericVisibleTool(itemId)
	-- If the exact item is server-only, use a client-visible Knife/Gun model
	-- as a 3D base. The item's own texture/icon is then applied to it.
	local wanted = string.lower(itemId)
	local isGun = string.find(wanted, "gun", 1, true) ~= nil
		or string.find(wanted, "luger", 1, true) ~= nil
		or string.find(wanted, "blaster", 1, true) ~= nil
		or string.find(wanted, "pistol", 1, true) ~= nil
		or string.find(wanted, "revolver", 1, true) ~= nil

	local names = isGun and { "Gun", "DefaultGun" } or { "Knife", "DefaultKnife" }
	local roots = { ReplicatedStorage, StarterPack }

	-- Prefer a model already visible on the local character/backpack.
	local character = LocalPlayer.Character
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	local localRoots = { character, backpack }
	for _, root in ipairs(localRoots) do
		if root then
			for _, object in ipairs(root:GetChildren()) do
				if object:IsA("Tool") then
					for _, name in ipairs(names) do
						if string.lower(object.Name) == string.lower(name) then
							return object
						end
					end
				end
			end
		end
	end

	for _, root in ipairs(roots) do
		for _, name in ipairs(names) do
			local found = root:FindFirstChild(name, true)
			if found and found:IsA("Tool") then
				return found
			end
		end
	end

	return nil
end

local function applyWeaponTexture(instance, itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return
	end

	local image = info.Image or info.Icon
	if not image then
		return
	end

	local imageId = tostring(image)
	if imageId:match("^%d+$") then
		imageId = "rbxassetid://" .. imageId
	end

	for _, object in ipairs(instance:GetDescendants()) do
		if object:IsA("Decal") or object:IsA("Texture") then
			object.Texture = imageId
		elseif object:IsA("MeshPart") then
			-- Keep the actual mesh/material of the client-visible base.
			-- TextureId is read-only on some MeshPart setups, so don't force it.
		end
	end

	local tool = instance:IsA("Tool") and instance or instance:FindFirstChildWhichIsA("Tool", true)
	if tool then
		pcall(function()
			tool.TextureId = imageId
		end)
	end
end

local function weldModelToPart(model, targetPart, offset)
	if not model or not targetPart then
		return false
	end

	local primary = model.PrimaryPart
	if not primary then
		primary = model:FindFirstChild("Handle", true)
	end
	if not primary or not primary:IsA("BasePart") then
		primary = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not primary then
		return false
	end

	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Anchored = false
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Massless = true
		end
	end

	model.PrimaryPart = primary
	model:PivotTo(targetPart.CFrame * offset)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "MM2LocalVisualWeld"
	weld.Part0 = primary
	weld.Part1 = targetPart
	weld.Parent = primary

	return true
end

local function makeFallbackVisual(itemId)
	local baseTool = findGenericVisibleTool(itemId)
	if not baseTool then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "MM2LocalVisual_" .. tostring(itemId)
	model:SetAttribute("MM2LocalWeapon", true)
	model:SetAttribute("ItemID", itemId)
	model:SetAttribute("OriginalItemID", itemId)

	for _, child in ipairs(baseTool:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
			local clone = child:Clone()
			clone.Parent = model
		end
	end

	applyWeaponTexture(model, itemId)
	return model
end

local function makeFallbackTool(itemId)
	local info = getWeaponInfo(itemId)
	if not info then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = getWeaponDisplayName(itemId)
	tool.ToolTip = getWeaponDisplayName(itemId)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("MM2LocalWeapon", true)
	tool:SetAttribute("ItemID", itemId)
	tool:SetAttribute("OriginalItemID", itemId)

	local image = info.Image or info.Icon
	if image then
		tool.TextureId = tostring(image):match("^%d+$")
			and "rbxassetid://" .. tostring(image)
			or tostring(image)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.25, 1.5, 0.12)
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Transparency = 1
	handle.Parent = tool

	return tool
end

local function attachExactToolVisual(tool, itemId)
	local character = getCharacter()
	local hand = findRightHand(character)
	if not character or not hand then
		return false
	end

	-- Clone the Tool's visible parts into a separate Model. This lets us keep
	-- the visual attached to the hand even if Roblox's Tool grip is changed.
	local model = Instance.new("Model")
	model.Name = "MM2LocalVisual_" .. tostring(itemId)
	model:SetAttribute("MM2LocalWeapon", true)
	model:SetAttribute("ItemID", itemId)
	model:SetAttribute("OriginalItemID", itemId)

	for _, child in ipairs(tool:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
			local clone = child:Clone()
			clone.Parent = model
		end
	end

	if not weldModelToPart(model, hand, CFrame.new(0, -0.25, -0.35) * CFrame.Angles(math.rad(-90), 0, 0)) then
		model:Destroy()
		return false
	end

	model.Parent = character
	currentVisual = model
	return true
end

local function equipLocalWeapon(itemId)
	if not Weapons[itemId] then
		warn("[MM2Local] Unknown weapon:", itemId)
		return false
	end

	removeLocalWeapon()

	local template = findClientToolTemplate(itemId)
	if template then
		-- Keep a real Tool in the Backpack so the existing inventory/equip flow
		-- still works, and separately force a visible hand model.
		local tool = template:Clone()
		tool:SetAttribute("MM2LocalWeapon", true)
		tool:SetAttribute("ItemID", itemId)
		tool:SetAttribute("OriginalItemID", itemId)
		tool.Name = getWeaponDisplayName(itemId)
		tool.CanBeDropped = false

		local backpack = LocalPlayer:WaitForChild("Backpack")
		tool.Parent = backpack
		currentTool = tool
		currentWeaponId = itemId

		local humanoid = getCharacter() and getCharacter():FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:EquipTool(tool)
		end

		-- Explicit visual weld fixes cases where Tool grip/Handle setup doesn't
		-- render correctly on the client.
		if not attachExactToolVisual(tool, itemId) then
			local visual = makeFallbackVisual(itemId)
			local hand = getCharacter() and findRightHand(getCharacter())
			if visual and hand then
				if weldModelToPart(visual, hand, CFrame.new(0, -0.25, -0.35) * CFrame.Angles(math.rad(-90), 0, 0)) then
					visual.Parent = getCharacter()
					currentVisual = visual
				end
			end
		end
		return true
	end

	-- No exact client-visible model: use a generic client-visible 3D Tool
	-- (Knife/Gun) as the visual base instead of an invisible Handle.
	local visual = makeFallbackVisual(itemId)
	local character = getCharacter()
	local hand = character and findRightHand(character)

	if visual and hand then
		local ok = weldModelToPart(visual, hand,
			CFrame.new(0, -0.25, -0.35) * CFrame.Angles(math.rad(-90), 0, 0))
		if ok then
			visual.Parent = character
			currentVisual = visual
			currentWeaponId = itemId
			return true
		end
		visual:Destroy()
	end

	-- Last-resort Tool fallback. It will still exist in the local Backpack.
	local tool = makeFallbackTool(itemId)
	if not tool then
		return false
	end

	local backpack = LocalPlayer:WaitForChild("Backpack")
	tool.Parent = backpack
	currentTool = tool
	currentWeaponId = itemId

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end

	return true
end

-- ============================================================
-- Local inventory grant
-- ============================================================

local function addLocalItem(itemId)
	if not Weapons[itemId] then
		return false
	end

	ownedLocal[itemId] = true

	-- The place's ProfileData uses Weapons.Owned[itemId].
	-- This changes only the local copy of ProfileData.
	ProfileData.Weapons = ProfileData.Weapons or {}
	ProfileData.Weapons.Owned = ProfileData.Weapons.Owned or {}
	ProfileData.Weapons.Owned[itemId] = 1

	-- Tell the existing client inventory UI about the local item.
	-- InventoryDataChanged is a BindableEvent in the supplied place.
	if InventoryDataChanged and InventoryDataChanged:IsA("BindableEvent") then
		InventoryDataChanged:Fire("Weapons", itemId, 1)
	end

	return true
end

-- ============================================================
-- GUI
-- ============================================================

local oldGui = PlayerGui:FindFirstChild("MM2LocalWeaponController")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MM2LocalWeaponController"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

local openButton = Instance.new("TextButton")
openButton.Name = "Open"
openButton.Size = UDim2.fromOffset(150, 38)
openButton.Position = UDim2.new(0, 15, 1, -55)
openButton.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 15
openButton.Font = Enum.Font.GothamBold
openButton.Text = "LOCAL WEAPONS"
openButton.Parent = gui

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 8)
openCorner.Parent = openButton

local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(430, 520)
window.Position = UDim2.new(0.5, -215, 0.5, -260)
window.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
window.BorderSizePixel = 0
window.Visible = false
window.Parent = gui

local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 10)
windowCorner.Parent = window

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(65, 65, 72)
stroke.Parent = window

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 42)
title.Position = UDim2.fromOffset(15, 5)
title.BackgroundTransparency = 1
title.Text = "MM2 Local Weapon Inventory"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = window

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(35, 35)
close.Position = UDim2.new(1, -42, 0, 7)
close.BackgroundTransparency = 1
close.Text = "×"
close.TextColor3 = Color3.fromRGB(255, 255, 255)
close.TextSize = 25
close.Font = Enum.Font.GothamBold
close.Parent = window

local search = Instance.new("TextBox")
search.Size = UDim2.new(1, -30, 0, 38)
search.Position = UDim2.fromOffset(15, 50)
search.BackgroundColor3 = Color3.fromRGB(35, 35, 41)
search.BorderSizePixel = 0
search.PlaceholderText = "Search weapon..."
search.PlaceholderColor3 = Color3.fromRGB(150, 150, 155)
search.TextColor3 = Color3.fromRGB(255, 255, 255)
search.TextSize = 14
search.Font = Enum.Font.Gotham
search.ClearTextOnFocus = false
search.Parent = window

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 7)
searchCorner.Parent = search

local list = Instance.new("ScrollingFrame")
list.Name = "WeaponList"
list.Size = UDim2.new(1, -30, 1, -105)
list.Position = UDim2.fromOffset(15, 95)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = window

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function makeWeaponRow(itemId, info, order)
	local row = Instance.new("Frame")
	row.Name = itemId
	row.Size = UDim2.new(1, -5, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = list

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(48, 48)
	icon.Position = UDim2.fromOffset(5, 5)
	icon.BackgroundTransparency = 1
	icon.Image = getWeaponImage(itemId)
	icon.Parent = row

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -190, 1, 0)
	name.Position = UDim2.fromOffset(62, 0)
	name.BackgroundTransparency = 1
	name.Text = getWeaponDisplayName(itemId)
	name.TextColor3 = Color3.fromRGB(240, 240, 240)
	name.TextSize = 14
	name.Font = Enum.Font.GothamMedium
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = row

	local give = Instance.new("TextButton")
	give.Size = UDim2.fromOffset(58, 32)
	give.Position = UDim2.new(1, -125, 0.5, -16)
	give.BackgroundColor3 = Color3.fromRGB(55, 55, 63)
	give.Text = ownedLocal[itemId] and "OWNED" or "GIVE"
	give.TextColor3 = Color3.fromRGB(255, 255, 255)
	give.TextSize = 11
	give.Font = Enum.Font.GothamBold
	give.Parent = row

	local giveCorner = Instance.new("UICorner")
	giveCorner.CornerRadius = UDim.new(0, 6)
	giveCorner.Parent = give

	give.Activated:Connect(function()
		if addLocalItem(itemId) then
			give.Text = "OWNED"
		end
	end)

	return row
end

-- Sort by display name, while preserving every real item ID from Sync.Weapons.
local itemIds = {}
for itemId, info in pairs(Weapons) do
	if type(itemId) == "string" and type(info) == "table" then
		table.insert(itemIds, itemId)
	end
end

table.sort(itemIds, function(a, b)
	return string.lower(getWeaponDisplayName(a)) < string.lower(getWeaponDisplayName(b))
end)

local rows = {}
for order, itemId in ipairs(itemIds) do
	rows[itemId] = makeWeaponRow(itemId, Weapons[itemId], order)
end

local function applySearch()
	local query = string.lower(search.Text or "")

	for itemId, row in pairs(rows) do
		local name = string.lower(getWeaponDisplayName(itemId))
		local id = string.lower(itemId)
		row.Visible = query == "" or string.find(name, query, 1, true) ~= nil or string.find(id, query, 1, true) ~= nil
	end
end

search:GetPropertyChangedSignal("Text"):Connect(applySearch)

openButton.Activated:Connect(function()
	window.Visible = not window.Visible
end)

close.Activated:Connect(function()
	window.Visible = false
end)

print("[MM2Local] Loaded. Weapons available:", #itemIds)
