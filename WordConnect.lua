local PastelHub = loadstring(game:HttpGet("https://raw.githubusercontent.com/Iumentis/Hub/refs/heads/main/PastelHub.lua"))()

local Rayfield = PastelHub.Rayfield or PastelHub
local PastelTheme = PastelHub.Theme or PastelHub.PastelTheme

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function SafeRequire(Path)
    local Ok, Result = pcall(function()
        local Inst = ReplicatedStorage
        for _, Part in ipairs(Path) do
            Inst = Inst:FindFirstChild(Part) or Inst:WaitForChild(Part, 5)
        end
        return require(Inst)
    end)
    if Ok then return Result end
    return nil, tostring(Result)
end

local Dictionary, DictErr = SafeRequire({ "Shared", "Dictionary" })
local WordGameRemotes = ReplicatedStorage:FindFirstChild("WordGameRemotes")
    or ReplicatedStorage:WaitForChild("WordGameRemotes", 5)

local OrderComparators = {
    ["Longest first"]        = function(A, B) if #A ~= #B then return #A > #B end return A < B end,
    ["Shortest first"]       = function(A, B) if #A ~= #B then return #A < #B end return A < B end,
    ["Alphabetical"]         = function(A, B) return A < B end,
    ["Reverse alphabetical"] = function(A, B) return A > B end,
    ["Random"]               = nil,
}

local State = {
    MinLen = 3, MaxLen = 16,
    Mode = "Auto Solve",
    WordOrder = "Longest first",
    DelayMin = 0.15, DelayMax = 0.35, RandomDelay = true,
    ToastTime = 4, SubmitToasts = true, AutoNext = true,
    ShowTileNumbers = false,
    Debug = false,
    Running = false, StopRequested = false,
    WordsFound = 0, WordsAccepted = 0,
}

local Memory = { RoundId = nil, Done = {} }
local function GetDone(RoundId)
    if Memory.RoundId ~= RoundId then
        Memory.RoundId = RoundId
        Memory.Done = {}
    end
    return Memory.Done
end

local function ShouldStop() return State.StopRequested or not State.Running end

local function GetContent()
    local Gui = LocalPlayer.PlayerGui:FindFirstChild("WordGameUI")
    local Frame = Gui and Gui:FindFirstChild("Frame")
    return Frame and Frame:FindFirstChild("Content")
end

local function FindBoard()
    local Content = GetContent()
    local BoardBG = Content and Content:FindFirstChild("BoardBG")
    return BoardBG and BoardBG:FindFirstChild("GridFrame")
end

local function GetWordRows()
    local Content = GetContent()
    local Panel = Content and Content:FindFirstChild("WordListPanel")
    local Scroll = Panel and Panel:FindFirstChild("WordScroll")
    return Scroll and Scroll:FindFirstChild("WordRows")
end

local function IsWordFound(Word)
    local Rows = GetWordRows()
    return Rows ~= nil and Rows:FindFirstChild("FoundWord_" .. Word) ~= nil
end

local function ReadBoard()
    local Board = FindBoard()
    if not Board then error("Board UI not found — is the round active?") end
    local Letters = {}
    for I = 1, 16 do
        local Cell = Board:FindFirstChild("TileCell" .. I)
        if not Cell then error("TileCell" .. I .. " missing") end
        local Tile = Cell:FindFirstChild("Tile" .. I)
        if not Tile then error("Tile" .. I .. " missing") end
        local Lbl = Tile:FindFirstChild("Letter")
        if not Lbl then error("Letter missing in Tile" .. I) end
        local Letter = string.upper(Lbl.Text)
        if Letter == "" then error("Empty letter at cell " .. I .. " (board not loaded?)") end
        Letters[I] = Letter
    end
    return Letters
end

local function SnapshotBoard()
    local Ok, Letters = pcall(ReadBoard)
    if not Ok then return nil end
    return Letters, table.concat(Letters)
end

local function GetRoundState()
    if not WordGameRemotes then error("WordGameRemotes not found") end
    local GetRS = WordGameRemotes:FindFirstChild("GetRoundState")
    if not GetRS then error("GetRoundState not found") end
    local Ok, S = pcall(function() return GetRS:InvokeServer() end)
    if not Ok then error("GetRoundState errored: " .. tostring(S)) end
    return S
end

local function StateSaysOver(S)
    return S.active == false or S.inRound == false or S.roundActive == false
end

local BadgeName = "_PastelIndexBadge"
local LabelName = "_PastelIndexNumber"

local LegacyNames = {
    "_PastelIndexBadge",
    "_PastelIndex_Badge",
    "_PastelIndex",
    "_PastelIndex_Badge_Badge",
}

local function IsLegacyBadgeName(Name)
    for _, N in ipairs(LegacyNames) do
        if Name == N then return true end
    end
    return false
end

local function ClearIndexLabels()
    local Board = FindBoard()
    if not Board then return end
    for I = 1, 16 do
        local Cell = Board:FindFirstChild("TileCell" .. I)
        local Tile = Cell and Cell:FindFirstChild("Tile" .. I)
        if not Tile then continue end
        for _, Child in ipairs(Tile:GetChildren()) do
            if IsLegacyBadgeName(Child.Name) then
                Child:Destroy()
            end
        end
    end
end

local function EnsureIndexLabels()
    if not State.ShowTileNumbers then return end
    local Board = FindBoard()
    if not Board then return end
    for I = 1, 16 do
        local Cell = Board:FindFirstChild("TileCell" .. I)
        local Tile = Cell and Cell:FindFirstChild("Tile" .. I)
        if not Tile then continue end

        local Existing = Tile:FindFirstChild(BadgeName)
        if Existing then
            local Num = Existing:FindFirstChild(LabelName)
            if Num and Num.Text ~= tostring(I) then
                Num.Text = tostring(I)
            end
            continue
        end

        for _, Child in ipairs(Tile:GetChildren()) do
            if IsLegacyBadgeName(Child.Name) then
                Child:Destroy()
            end
        end

        local Badge = Instance.new("Frame")
        Badge.Name = BadgeName
        Badge.Size = UDim2.fromOffset(20, 20)
        Badge.Position = UDim2.new(0, 4, 0, 4)
        Badge.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
        Badge.BackgroundTransparency = 0.35
        Badge.BorderSizePixel = 0
        Badge.ZIndex = 50

        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(1, 0)
        Corner.Parent = Badge

        local Num = Instance.new("TextLabel")
        Num.Name = LabelName
        Num.Size = UDim2.fromScale(1, 1)
        Num.BackgroundTransparency = 1
        Num.Text = tostring(I)
        Num.TextColor3 = Color3.fromRGB(255, 240, 250)
        Num.TextStrokeColor3 = Color3.fromRGB(80, 40, 80)
        Num.TextStrokeTransparency = 0.4
        Num.TextSize = 13
        Num.Font = Enum.Font.GothamBold
        Num.ZIndex = 51
        Num.Parent = Badge

        Badge.Parent = Tile
    end
end

local function RefreshIndexLabels()
    if State.ShowTileNumbers then
        EnsureIndexLabels()
    else
        ClearIndexLabels()
    end
end

local function RowCol(I) return math.floor((I - 1) / 4) + 1, ((I - 1) % 4) + 1 end
local Neighbors = {}
for I = 1, 16 do
    local RI, CI = RowCol(I)
    Neighbors[I] = {}
    for DI = -1, 1 do for DJ = -1, 1 do
        if DI ~= 0 or DJ ~= 0 then
            local RJ, CJ = RI + DI, CI + DJ
            if RJ >= 1 and RJ <= 4 and CJ >= 1 and CJ <= 4 then
                table.insert(Neighbors[I], (RJ - 1) * 4 + CJ)
            end
        end
    end end
end

local function FindWords(Letters, MinLen, MaxLen)
    if not Dictionary then error("Dictionary not loaded") end
    local Found, Order = {}, {}
    local Visited, Path, Chars = {}, {}, {}
    local function DFS(I)
        local W = table.concat(Chars) .. Letters[I]
        if not Dictionary.isPrefix(W) then return end
        table.insert(Chars, Letters[I])
        table.insert(Path, I)
        Visited[I] = true
        if #Path >= MinLen and #Path <= MaxLen then
            if Dictionary.isWord(W) and not Found[W] then
                Found[W] = { table.unpack(Path) }
                table.insert(Order, W)
            end
        end
        if #Path < MaxLen then
            for _, Nxt in ipairs(Neighbors[I]) do
                if not Visited[Nxt] then DFS(Nxt) end
            end
        end
        table.remove(Chars)
        table.remove(Path)
        Visited[I] = nil
    end
    for I = 1, 16 do DFS(I) end
    return Found, Order
end

local function SortWordsInPlace(Order)
    local Choice = State.WordOrder or "Longest first"
    if Choice == "Random" then
        for I = #Order, 2, -1 do
            local J = math.random(1, I)
            Order[I], Order[J] = Order[J], Order[I]
        end
        return
    end
    local Cmp = OrderComparators[Choice] or OrderComparators["Longest first"]
    table.sort(Order, Cmp)
end

local Window = Rayfield:CreateWindow({
    name = "Pastel Hub",
    subtitle = "Word Connect",
    theme = PastelTheme,
    sidebarLayout = true,
    configuration = { autoSave = true, autoLoad = true, fileName = "PastelHub_WC" },
    showName = "Pastel Hub",
    showIcon = 80387863064905,
})

local SolverTab = Window:CreateTab({ name = "Solver", icon = 88479147175134 })
local LogTab    = Window:CreateTab({ name = "Log",    icon = 100604009889706 })

local function Toast(Title, Content, Duration)
    pcall(function() Window:Notify({ title = Title, content = Content, duration = Duration }) end)
end

local Console = LogTab:CreateConsole({ name = "Log", height = 260, follow = true, maxLines = 300 })
local function Log(Msg) Console:Append(Msg) end
local function Dbg(Msg) if State.Debug then Console:Append("[dbg] " .. Msg) end end

Log("[Pastel Hub] loaded")
if Dictionary then
    Log(("[Dict] %s words, %s prefixes"):format(
        tostring(Dictionary.wordCount or "?"), tostring(Dictionary.prefixCount or "?")
    ))
else
    Log("[Dict] FAILED: " .. tostring(DictErr))
end

local function RunDiagnostics()
    Log("─── DIAGNOSTICS ───")
    Log("Board: " .. (FindBoard() and "OK" or "NOT FOUND"))
    Log("WordRows: " .. (GetWordRows() and "OK" or "NOT FOUND"))
    Log("Dictionary: " .. (Dictionary and "OK" or ("FAILED: " .. tostring(DictErr))))
    Log("Remotes: " .. (WordGameRemotes and "OK" or "NOT FOUND"))
    Log("Mode: " .. tostring(State.Mode) .. " | Order: " .. tostring(State.WordOrder)
        .. " | Tile nums: " .. tostring(State.ShowTileNumbers))
    local OkB, Letters = pcall(ReadBoard)
    Log(OkB and ("Letters: " .. table.concat(Letters, " ")) or ("Board error: " .. tostring(Letters)))
    local OkS, S = pcall(GetRoundState)
    if OkS and type(S) == "table" then
        for K, V in pairs(S) do
            Log(("  roundState.%s = %s"):format(tostring(K), tostring(V)))
        end
    else
        Log("RoundState error: " .. tostring(S))
    end
end

LogTab:CreateToggle({
    name = "Debug",
    value = false, forgetState = true,
    callback = function(On)
        State.Debug = On and true or false
        if On then RunDiagnostics() end
    end,
})

local function RoundIsCurrent(Ctx)
    local _, Sig = SnapshotBoard()
    if Sig ~= Ctx.Signature then return false end
    if os.clock() - Ctx.LastCheck >= 1.5 then
        Ctx.LastCheck = os.clock()
        local Ok, S = pcall(GetRoundState)
        if Ok and type(S) == "table" then
            if S.roundId ~= Ctx.RoundId or StateSaysOver(S) then
                return false
            end
        end
    end
    return true
end

local function WaitForRound(PrevRoundId, PrevSig)
    local Warned = false
    while not ShouldStop() do
        local Letters, Sig = SnapshotBoard()
        local Ok, S = pcall(GetRoundState)
        if Letters and Ok and type(S) == "table" and S.roundId
            and not StateSaysOver(S)
            and (S.roundId ~= PrevRoundId or Sig ~= PrevSig) then
            task.wait(0.4)
            local _, Sig2 = SnapshotBoard()
            if Sig2 == Sig then
                return {
                    RoundId = S.roundId, Letters = Letters, Signature = Sig,
                    LastCheck = os.clock(),
                }
            end
        else
            if not Warned then Log("[wait] waiting for a round..."); Warned = true end
            task.wait(0.5)
        end
    end
    return nil
end

local function SolveRound(Ctx)
    local Mode = State.Mode
    local Lo = math.min(State.MinLen, State.MaxLen)
    local Hi = math.max(State.MinLen, State.MaxLen)

    if State.ShowTileNumbers then EnsureIndexLabels() end

    local Found, Order = FindWords(Ctx.Letters, Lo, Hi)
    SortWordsInPlace(Order)
    State.WordsFound = #Order
    State.WordsAccepted = 0
    Log(("[round] %s | %d words | %s"):format(Ctx.Signature, #Order, Mode))

    if #Order == 0 then
        Toast("No words", "Board has no valid words.")
        return
    end

    local Done = GetDone(Ctx.RoundId)
    local Submit = WordGameRemotes and WordGameRemotes:FindFirstChild("SubmitWord")
    if Mode == "Auto Solve" and not Submit then error("SubmitWord remote not found") end

    for I, Word in ipairs(Order) do
        if ShouldStop() then
            Log(("[solve] stopped at %d/%d"):format(I - 1, #Order))
            return
        end
        if not RoundIsCurrent(Ctx) then Log("[round] ended"); return end
        if Done[Word] or IsWordFound(Word) then Dbg("skip " .. Word); continue end
        local Path = Found[Word]

        if Mode == "Show Solve" then
            local Text = ("%s  ›  %s"):format(Word, table.concat(Path, " → "))
            local LastToast = -math.huge
            repeat
                if os.clock() - LastToast >= State.ToastTime then
                    Toast(("Word %d/%d"):format(I, #Order), Text, State.ToastTime)
                    LastToast = os.clock()
                end
                task.wait(0.1)
            until ShouldStop() or IsWordFound(Word) or not RoundIsCurrent(Ctx)

            if IsWordFound(Word) then
                Done[Word] = true
                State.WordsAccepted = State.WordsAccepted + 1
                Log("[ok] " .. Word)
            elseif not ShouldStop() then Log("[round] ended"); return end
        else
            local OkS, Res = pcall(function()
                return Submit:InvokeServer({ word = Word, path = Path, roundId = Ctx.RoundId })
            end)
            if OkS and type(Res) == "table" then
                Done[Word] = true
                if Res.accepted then
                    State.WordsAccepted = State.WordsAccepted + 1
                    Log("[ok] " .. Word)
                    if State.SubmitToasts then Toast("Submitted", Word, 1.5) end
                else
                    Dbg(("[rej %s] %s"):format(tostring(Res.reason), Word))
                end
            else
                Dbg(("[err] %s: %s"):format(Word, tostring(Res)))
            end
            local DMin = math.min(State.DelayMin, State.DelayMax)
            local DMax = math.max(State.DelayMin, State.DelayMax)
            task.wait(State.RandomDelay and (DMin + math.random() * (DMax - DMin)) or DMax)
        end
    end
    Toast("Round done", ("Accepted %d / %d"):format(State.WordsAccepted, State.WordsFound))
end

local function RunSolver()
    return pcall(function()
        if not Dictionary then error("Dictionary not loaded") end
        local PrevRoundId, PrevSig
        while not ShouldStop() do
            local Ctx = WaitForRound(PrevRoundId, PrevSig)
            if not Ctx then break end
            PrevRoundId, PrevSig = Ctx.RoundId, Ctx.Signature
            SolveRound(Ctx)
            if not State.AutoNext then break end
            if not ShouldStop() then Log("[solve] waiting for next round...") end
        end
    end)
end

local AutoSolveToggle
local UiReady = false

AutoSolveToggle = SolverTab:CreateToggle({
    name = "Auto Solve",
    value = false, forgetState = true,
    callback = function(On)
        if not UiReady then return end
        if On then
            if State.Running then return end
            State.Running = true
            State.StopRequested = false
            task.spawn(function()
                local Ok, Err = RunSolver()
                State.Running = false
                if AutoSolveToggle and AutoSolveToggle.value then
                    AutoSolveToggle:Set(false, true)
                end
                if not Ok then
                    Log("[FATAL] " .. tostring(Err))
                    Toast("Solver error", tostring(Err), 5)
                end
            end)
        else
            if State.Running then
                State.StopRequested = true
                Toast("Stopping", "Halting at next word.")
            end
        end
    end,
})

SolverTab:CreateDropdown({
    name = "Solve Method",
    options = { "Auto Solve", "Show Solve" },
    value = State.Mode, flag = "WH3_Mode",
    callback = function(V)
        local Picked = type(V) == "table" and V[1] or V
        if Picked == "Auto Solve" or Picked == "Show Solve" then
            State.Mode = Picked
        end
    end,
})

SolverTab:CreateDropdown({
    name = "Word Order",
    options = { "Longest first", "Shortest first", "Alphabetical", "Reverse alphabetical", "Random" },
    value = State.WordOrder, flag = "WH3_WordOrder",
    callback = function(V)
        local Picked = type(V) == "table" and V[1] or V
        if type(Picked) == "string" and (OrderComparators[Picked] ~= nil or Picked == "Random") then
            State.WordOrder = Picked
        end
    end,
})

SolverTab:CreateToggle({
    name = "Keep Solving",
    value = State.AutoNext, flag = "WH3_AutoNext",
    callback = function(V) State.AutoNext = V end,
})

SolverTab:CreateSection({ name = "Display" })
SolverTab:CreateToggle({
    name = "Show Numbers on Tiles",
    value = State.ShowTileNumbers, flag = "WH3_ShowTileNumbers",
    callback = function(V)
        State.ShowTileNumbers = V
        RefreshIndexLabels()
    end,
})

SolverTab:CreateSection({ name = "Words" })
SolverTab:CreateSlider({
    name = "Min Length",
    range = { 3, 16 }, increment = 1, value = State.MinLen,
    flag = "WH3_MinLen", suffix = " letters",
    callback = function(V) State.MinLen = V end,
})
SolverTab:CreateSlider({
    name = "Max Length",
    range = { 3, 16 }, increment = 1, value = State.MaxLen,
    flag = "WH3_MaxLen", suffix = " letters",
    callback = function(V) State.MaxLen = V end,
})

SolverTab:CreateSection({ name = "Auto Solve Settings" })
SolverTab:CreateSlider({
    name = "Min Delay",
    range = { 0.05, 15 }, increment = 0.05,
    value = State.DelayMin, flag = "WH3_DelayMin", suffix = " s",
    callback = function(V) State.DelayMin = V end,
})
SolverTab:CreateSlider({
    name = "Max Delay",
    range = { 0.05, 15 }, increment = 0.05,
    value = State.DelayMax, flag = "WH3_DelayMax", suffix = " s",
    callback = function(V) State.DelayMax = V end,
})
SolverTab:CreateToggle({
    name = "Random Delay",
    value = State.RandomDelay, flag = "WH3_RandomDelay",
    callback = function(V) State.RandomDelay = V end,
})
SolverTab:CreateToggle({
    name = "Submit Toasts",
    value = State.SubmitToasts, flag = "WH3_SubmitToasts",
    callback = function(V) State.SubmitToasts = V end,
})

SolverTab:CreateSection({ name = "Show Solve Settings" })
SolverTab:CreateSlider({
    name = "Toast Time",
    range = { 2, 20 }, increment = 0.5,
    value = State.ToastTime, flag = "WH3_ToastTime", suffix = " s",
    callback = function(V) State.ToastTime = V end,
})

UiReady = true

task.spawn(function()
    local LastSig = nil
    while Window and not Window.unloaded do
        if State.ShowTileNumbers then
            local Ok, _, Sig = pcall(SnapshotBoard)
            if Ok and Sig and Sig ~= LastSig then
                LastSig = Sig
                pcall(EnsureIndexLabels)
            end
            pcall(EnsureIndexLabels)
        else
            LastSig = nil
        end
        task.wait(0.5)
    end
end)
