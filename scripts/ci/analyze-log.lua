local run_path = arg[1] or ".ci-debug/run.json"
local log_path = arg[2] or ".ci-debug/failed.log"

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return "" end
  local data = file:read("*a")
  file:close()
  return data or ""
end

local function json_string(json, key)
  local pattern = '"' .. key .. '"%s*:%s*"(.-)"'
  local value = json:match(pattern)
  if not value then return nil end
  value = value:gsub('\\n', '\n'):gsub('\\"', '"'):gsub('\\/', '/')
  return value
end

local function json_number(json, key)
  return json:match('"' .. key .. '"%s*:%s*(%d+)')
end

local function split_lines(text)
  local lines = {}
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function trim(line)
  return (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local rules = {
  { name = "CMake configuration error", pattern = "CMake Error" },
  { name = "C/C++ compiler error", pattern = "fatal error" },
  { name = "MSVC compiler error", pattern = "error C%d+" },
  { name = "Linker error", pattern = "undefined reference" },
  { name = "Linker error", pattern = "LNK%d+" },
  { name = "Lua runtime error", pattern = "^luajit:" },
  { name = "Lua runtime error", pattern = "stack traceback" },
  { name = "Python traceback", pattern = "Traceback %(most recent call last%)" },
  { name = "Pytest failure", pattern = "FAILED" },
  { name = "Node/Jest/Vitest failure", pattern = "AssertionError" },
  { name = "GitHub Actions step failure", pattern = "Process completed with exit code" },
  { name = "Permission error", pattern = "[Pp]ermission denied" },
  { name = "Disk space error", pattern = "No space left on device" },
  { name = "Missing dependency", pattern = "command not found" },
  { name = "Missing dependency", pattern = "Could NOT find" },
}

local function find_findings(lines)
  local findings = {}
  for index, line in ipairs(lines) do
    for _, rule in ipairs(rules) do
      if line:find(rule.pattern) then
        findings[#findings + 1] = { rule = rule.name, line = index, text = line }
        break
      end
    end
  end
  return findings
end

local function context(lines, line_no, radius)
  local out = {}
  local first = math.max(1, line_no - radius)
  local last = math.min(#lines, line_no + radius)
  for i = first, last do
    out[#out + 1] = string.format("%5d | %s", i, lines[i])
  end
  return table.concat(out, "\n")
end

local function histogram(findings)
  local counts = {}
  local order = {}
  for _, finding in ipairs(findings) do
    if not counts[finding.rule] then
      counts[finding.rule] = 0
      order[#order + 1] = finding.rule
    end
    counts[finding.rule] = counts[finding.rule] + 1
  end
  table.sort(order)
  return order, counts
end

local run_json = read_file(run_path)
local log_text = read_file(log_path)
local lines = split_lines(log_text)
local findings = find_findings(lines)
local first = findings[1]
local order, counts = histogram(findings)

local run_id = json_number(run_json, "databaseId") or "unknown"
local url = json_string(run_json, "url") or "unknown"
local workflow = json_string(run_json, "workflowName") or "unknown"
local status = json_string(run_json, "status") or "unknown"
local conclusion = json_string(run_json, "conclusion") or "unknown"
local sha = json_string(run_json, "headSha") or "unknown"
local branch = json_string(run_json, "headBranch") or "unknown"

print("# CI Debug Report")
print("")
print("- Run: `" .. run_id .. "`")
print("- Workflow: `" .. workflow .. "`")
print("- Status: `" .. status .. "`")
print("- Conclusion: `" .. conclusion .. "`")
print("- Branch: `" .. branch .. "`")
print("- Commit: `" .. sha .. "`")
print("- URL: " .. url)
print("")

print("## Likely Root Cause")
print("")
if first then
  print("The first high-signal failure matched **" .. first.rule .. "** at log line " .. first.line .. ".")
  print("")
  print("> " .. trim(first.text))
else
  print("No known high-signal error pattern was found. Inspect the full failed log in `.ci-debug/failed.log`.")
end
print("")

print("## Error Categories")
print("")
if #order == 0 then
  print("- No classified errors found.")
else
  for _, name in ipairs(order) do
    print("- " .. name .. ": " .. counts[name])
  end
end
print("")

print("## First Useful Error")
print("")
if first then
  print("```text")
  print(context(lines, first.line, 8))
  print("```")
else
  print("```text")
  for i = 1, math.min(#lines, 40) do
    print(string.format("%5d | %s", i, lines[i]))
  end
  print("```")
end
print("")

print("## Suggested Next Action")
print("")
if first then
  if first.rule:find("CMake") then
    print("Check the CMake configuration step first: missing toolchain files, SDKs, generators, or dependency paths usually appear before compile starts.")
  elseif first.rule:find("compiler") or first.rule:find("MSVC") then
    print("Open the file and line named by the compiler error, then reproduce the same build target locally if possible.")
  elseif first.rule:find("Lua") then
    print("Run the Lua smoke test named in the traceback locally and inspect the first stack frame in project code.")
  elseif first.rule:find("Missing dependency") then
    print("Add the missing command or package to the CI setup step, or guard the test when the dependency is intentionally optional.")
  else
    print("Start with the first useful error above, then inspect 20-50 lines before it in `.ci-debug/failed.log` for the command that produced it.")
  end
else
  print("Inspect `.ci-debug/failed.log` manually or extend `scripts/ci/analyze-log.lua` with a new pattern for this failure mode.")
end
