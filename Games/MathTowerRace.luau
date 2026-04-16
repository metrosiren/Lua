local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/metrosiren/Lua/refs/heads/main/Prism"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------
-- LOCATE GAME INSTANCES
---------------------------------------------------------
local Gameplay = PlayerGui:WaitForChild("Gameplay", 10)

local function waitForPath(root, ...)
    local current = root
    for _, name in ipairs({...}) do
        current = current:WaitForChild(name, 10)
        if not current then return nil end
    end
    return current
end

-- Question display
local TopicGui = waitForPath(Gameplay, "TopicGui")
local TopicLabel = waitForPath(TopicGui, "TopicFrame", "CenterFrame", "TopicLabel")

-- Multiple choice answer GUI
local AnswerGui = waitForPath(Gameplay, "AnswerGui")
local AnswerFrame = waitForPath(AnswerGui, "AnswerFrame", "CenterFrame", "InputFrame")

-- Text input answer GUI
local AnswerInputGui = waitForPath(Gameplay, "AnswerInputGui")
local AnswerInputBox = waitForPath(AnswerInputGui, "AnswerFrame", "CenterFrame", "InputFrame", "InputFrameBackground", "AnswerInputBox")
local SubmitAnswerBtn = waitForPath(AnswerInputGui, "AnswerFrame", "CenterFrame", "InputFrame", "SubmitAnswerBtn")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local SubmitAnswerRemote = Remotes and Remotes:FindFirstChild("SubmitAnswerRemote")

---------------------------------------------------------
-- MATH SOLVER
---------------------------------------------------------
local function solveExpression(text)
    -- Clean up the question text
    local expr = text
    -- Replace common symbols
    expr = expr:gsub("×", "*"):gsub("✕", "*"):gsub("✖", "*")
    expr = expr:gsub("÷", "/"):gsub("➗", "/")
    expr = expr:gsub("−", "-"):gsub("–", "-")
    expr = expr:gsub("²", "^2"):gsub("³", "^3")
    expr = expr:gsub("√", "math.sqrt")
    -- Handle "◻" or "?" as the unknown — this is what we need to solve for
    -- For simple "a ◻ b = c" patterns, try to find the missing operator or value

    -- Try direct evaluation: if it's a plain expression like "5 + 3"
    local fn = loadstring("return " .. expr)
    if fn then
        local ok, result = pcall(fn)
        if ok and result then
            return result
        end
    end
    return nil
end

local function findCorrectChoice(questionText)
    -- For multiple choice, evaluate the question and compare to each answer button
    if not AnswerFrame then return nil end

    local result = solveExpression(questionText)

    for i = 1, 4 do
        local answerFrame = AnswerFrame:FindFirstChild("Answer" .. i)
        if answerFrame then
            local triggerBtn = answerFrame:FindFirstChild("TriggerBtn")
            if triggerBtn and triggerBtn:IsA("TextButton") then
                local btnText = triggerBtn.Text:gsub("%s+", "")
                if btnText ~= "" then
                    -- Check if button text matches computed result
                    if result and tostring(math.floor(result)) == btnText then
                        return triggerBtn
                    end
                    if result and tostring(result) == btnText then
                        return triggerBtn
                    end
                    -- Also try evaluating if the answer choice makes the equation true
                end
            end
        end
    end

    -- Fallback: try each answer choice and see which one is valid
    -- Parse question for pattern like "a ○ b" where we pick the right answer
    for i = 1, 4 do
        local answerFrame = AnswerFrame:FindFirstChild("Answer" .. i)
        if answerFrame then
            local triggerBtn = answerFrame:FindFirstChild("TriggerBtn")
            if triggerBtn and triggerBtn:IsA("TextButton") then
                local btnText = triggerBtn.Text:gsub("%s+", "")
                if btnText ~= "" then
                    -- Substitute answer into question and check
                    local testExpr = questionText:gsub("[◻%?_]+", btnText)
                    testExpr = testExpr:gsub("×", "*"):gsub("✕", "*"):gsub("✖", "*")
                    testExpr = testExpr:gsub("÷", "/"):gsub("➗", "/")
                    testExpr = testExpr:gsub("−", "-"):gsub("–", "-")
                    
                    -- Handle "expr = expr" equality check
                    local lhs, rhs = testExpr:match("^(.-)%s*=%s*(.-)$")
                    if lhs and rhs then
                        local fnL = loadstring("return " .. lhs)
                        local fnR = loadstring("return " .. rhs)
                        if fnL and fnR then
                            local okL, valL = pcall(fnL)
                            local okR, valR = pcall(fnR)
                            if okL and okR and valL and valR then
                                if math.abs(valL - valR) < 0.001 then
                                    return triggerBtn
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function solveForInput(questionText)
    -- For text input mode, compute the answer directly
    local expr = questionText
    expr = expr:gsub("×", "*"):gsub("✕", "*"):gsub("✖", "*")
    expr = expr:gsub("÷", "/"):gsub("➗", "/")
    expr = expr:gsub("−", "-"):gsub("–", "-")
    expr = expr:gsub("²", "^2"):gsub("³", "^3")

    -- Pattern: "expression = ?" or "expression = ◻"
    local lhs, rhs = expr:match("^(.-)%s*=%s*(.-)$")
    if lhs and rhs then
        local unknownSide = nil
        if rhs:match("[◻%?_]") then
            local fn = loadstring("return " .. lhs)
            if fn then
                local ok, val = pcall(fn)
                if ok and val then return tostring(val) end
            end
        elseif lhs:match("[◻%?_]") then
            local fn = loadstring("return " .. rhs)
            if fn then
                local ok, val = pcall(fn)
                if ok and val then return tostring(val) end
            end
        else
            -- Both sides have values, might be a comparison — compute lhs
            local fn = loadstring("return " .. lhs)
            if fn then
                local ok, val = pcall(fn)
                if ok and val then return tostring(val) end
            end
        end
    end

    -- Simple expression without equals
    local fn = loadstring("return " .. expr)
    if fn then
        local ok, val = pcall(fn)
        if ok and val then return tostring(val) end
    end

    return nil
end

---------------------------------------------------------
-- AUTO ANSWER LOGIC
---------------------------------------------------------
local autoAnswerEnabled = false
local answerDelay = 0.5
local lastQuestion = ""

local function tryAutoAnswer()
    if not autoAnswerEnabled then return end
    if not TopicLabel then return end

    local questionText = TopicLabel.Text
    if questionText == "" or questionText == lastQuestion then return end
    lastQuestion = questionText

    task.wait(answerDelay)
    if not autoAnswerEnabled then return end

    -- Try to find the answer
    local answer = nil

    -- Multiple choice: find the correct button text
    if AnswerGui and AnswerGui.Enabled and AnswerFrame then
        local btn = findCorrectChoice(questionText)
        if btn then
            answer = btn.Text:gsub("%s+", "")
        end
    end

    -- Text input: solve the expression
    if not answer and AnswerInputGui and AnswerInputGui.Enabled then
        answer = solveForInput(questionText)
    end

    -- Generic solve fallback
    if not answer then
        answer = solveForInput(questionText)
    end

    -- Submit via remote
    if answer and SubmitAnswerRemote then
        pcall(function()
            SubmitAnswerRemote:InvokeServer(answer)
        end)
    end
end

---------------------------------------------------------
-- QUESTION CHANGE LISTENER
---------------------------------------------------------
local connection = nil
local function startListening()
    if connection then return end
    if not TopicLabel then return end

    connection = TopicLabel:GetPropertyChangedSignal("Text"):Connect(function()
        if autoAnswerEnabled then
            task.spawn(tryAutoAnswer)
        end
    end)

    -- Also try answering the current question immediately
    task.spawn(tryAutoAnswer)
end

local function stopListening()
    if connection then
        connection:Disconnect()
        connection = nil
    end
    lastQuestion = ""
end

---------------------------------------------------------
-- UI MENU
---------------------------------------------------------
local Window = Library:CreateWindow("Math Tower Race", "6eUI4BbLFe", nil, true)

local MainTab = Window:CreateTab("Main")

MainTab:CreateLabel("AUTO ANSWER")

MainTab:CreateToggle("Auto Answer", function(state)
    autoAnswerEnabled = state
    if state then
        startListening()
        Window:Notify("Auto Answer", "Enabled — will auto-solve math problems", 3)
    else
        stopListening()
        Window:Notify("Auto Answer", "Disabled", 3)
    end
end)

MainTab:CreateSlider("Answer Delay (ms)", 0, 2000, 500, function(val)
    answerDelay = val / 1000
end)

local SettingsTab = Window:CreateTab("Settings")

SettingsTab:CreateLabel("UI OPTIONS")

SettingsTab:CreateButton("Destroy UI", function()
    local gui = (gethui and gethui()) or game:GetService("CoreGui")
    local ui = gui:FindFirstChild("SimpleUI")
    if ui then ui:Destroy() end
    stopListening()
end)
