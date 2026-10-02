--// MM2 Local Weapon Inventory / Equip Controller
--// ONE LocalScript
--// Put in: StarterPlayer > StarterPlayerScripts
--//
--// This script uses the data that already exists in the place:
--//   ReplicatedStorage.Database.Sync.Weapons
--//   ReplicatedStorage.Modules.ProfileData
--//   ReplicatedStorage.Remotes.Inventory.InventoryDataChanged
--//
--// No permission check and no RemoteEvent request are used.
--// Clicking an item adds it to the LOCAL player's inventory only.
--// The normal MM2 inventory UI can then display it through InventoryDataChanged.
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

local function removeLocalWeapon()
	if currentTool then
		currentTool:Destroy()
		currentTool = nil
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
	-- The real place has its weapon Tools in ServerStorage.Database.Item.
	-- That container is NOT accessible to a LocalScript.
	-- Search only client-visible containers.

	local containers = {
		ReplicatedStorage,
		StarterPack,
	}

	for _, root in ipairs(containers) do
		local exact = root:FindFirstChild(itemId, true)
		if exact and exact:IsA("Tool") then
			return exact
		end
	end

	-- Some projects keep a generic Tool whose Attribute identifies the item.
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

local function equipLocalWeapon(itemId)
	if not Weapons[itemId] then
		warn("[MM2Local] Unknown weapon:", itemId)
		return false
	end

	removeLocalWeapon()

	local template = findClientToolTemplate(itemId)
	local tool

	if template then
		tool = template:Clone()
		tool:SetAttribute("MM2LocalWeapon", true)
		tool:SetAttribute("ItemID", itemId)
		tool:SetAttribute("OriginalItemID", itemId)
	else
		tool = makeFallbackTool(itemId)
	end

	if not tool then
		return false
	end

	tool.Name = getWeaponDisplayName(itemId)
	tool.CanBeDropped = false

	local backpack = LocalPlayer:WaitForChild("Backpack")
	tool.Parent = backpack

	currentTool = tool
	currentWeaponId = itemId

	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:EquipTool(tool)
		end
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

	local equip = Instance.new("TextButton")
	equip.Size = UDim2.fromOffset(58, 32)
	equip.Position = UDim2.new(1, -62, 0.5, -16)
	equip.BackgroundColor3 = Color3.fromRGB(75, 75, 84)
	equip.Text = "EQUIP"
	equip.TextColor3 = Color3.fromRGB(255, 255, 255)
	equip.TextSize = 11
	equip.Font = Enum.Font.GothamBold
	equip.Parent = row

	local equipCorner = Instance.new("UICorner")
	equipCorner.CornerRadius = UDim.new(0, 6)
	equipCorner.Parent = equip

	give.Activated:Connect(function()
		if addLocalItem(itemId) then
			give.Text = "OWNED"
		end
	end)

	equip.Activated:Connect(function()
		if not ownedLocal[itemId] then
			if not addLocalItem(itemId) then
				return
			end
			give.Text = "OWNED"
		end

		equipLocalWeapon(itemId)
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

-- ============================================================
-- Respawn
-- ============================================================
-- The local Tool disappears with the old Character. Re-equip the last
-- selected local item after respawn.

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.25)

	if currentWeaponId and ownedLocal[currentWeaponId] then
		equipLocalWeapon(currentWeaponId)
	end
end)

print("[MM2Local] Loaded. Weapons available:", #itemIds)
