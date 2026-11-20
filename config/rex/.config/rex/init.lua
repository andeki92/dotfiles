-- Rex's config: everything comes from rex-acp, which writes
-- ~/.config/rex/rex-acp.lua (`rex-acp rex-setup`) and keeps it up to date.
-- See rex-acp's README, "Set up Rex".
do
  local acp = loadfile(os.getenv("HOME") .. "/.config/rex/rex-acp.lua")
  if acp ~= nil then acp() end
end
