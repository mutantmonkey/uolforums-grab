local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local ids = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

start, end_ = string.match(item_value, "([0-9]+)-([0-9]+)")
for i=start, end_ do
  ids[i] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

read_file_part = function(file, size)
  if file then
    local f = io.open(file)
    local data = f:read(size)
    f:close()
    return data or ""
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
     or string.match(url, "[<>\\%*%$;%^%[%],%(%)]")
     or string.match(url, "//$")
     or not string.match(url, "^https?://[^/]*forum%." .. item_type .. "%.uol%.com%.br/") then
    return false
  end

  if item_type == "jogos" or item_type == "esporte" or item_type == "televisao" or item_type == "tecnologia" then
    for id in string.gmatch(url, "_t_([0-9]+)") do
      if ids[tonumber(id)] == true then
        return true
      end
    end
  end

  return false
end

wget.callbacks.lookup_host = function(host)
  if host == "forum.jogos.uol.com.br" or host == "forum.esporte.uol.com.br" or host == "forum.televisao.uol.com.br" or host == "forum.tecnologia.uol.com.br" then
    return "200.147.35.152"
  end
  return nil
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
     and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  downloaded[url] = true
  
  local function check(urla)
    local origurl = url
    local url = string.gsub(string.match(urla, "^([^#]+)"), "&amp;", "&")
    if (downloaded[url] ~= true and addedtolist[url] ~= true)
       and allowed(url, origurl) then
      table.insert(urls, { url=url })
      addedtolist[origurl] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  
  if allowed(url, nil) then
    html = read_file(file)

    if (item_type == "jogos" or item_type == "esporte" or item_type == "televisao" or item_type == "tecnologia") and string.match(url, "_t_[0-9]+%?page=[0-9]+$") then
      check(string.match(url, "^([^%?]+)"))
    end

    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      check(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  url_count = url_count + 1
  local error_thread_page = false

  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 300 and status_code <= 399) then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true then
      return wget.actions.EXIT
    end
    if string.match(newloc, "^https?://forum%." .. item_type .. "%.uol%.com%.br/;jsessionid=") then
      return wget.actions.EXIT
    end
  end

  -- Verify that thread pages contain posts
  if (status_code == 200 and string.match(url["url"], "^http?://forum%." .. item_type .. "%.uol%.com%.br/.*_t_%d+")) then
    -- Read first 50 KiB of the file
    local html = read_file_part(http_stat["local_file"], 51200)
    if not string.match(html, '<div%s+class="[^"]*post') then
      io.stdout:write("Thread page missing posts. Flagging for abortion.\n")
      io.stdout:flush()
      error_thread_page = true
      abortgrab = true
    end
  end

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) or
    status_code == 0 or
    error_thread_page then
    if not error_thread_page then
      io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
      io.stdout:flush()
      os.execute("sleep 1")
    end
    tries = tries + 1
    if tries >= 3 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.exits.IO_FAIL
  end
  return exit_status
end
