#!/bin/lua
spawn = package.loadlib('/lib/spawn.so','luaopen_spawn')()

spawn.ignore_signals()

-- Times through outer loop
times = 100
-- Delay between iterations (microseconds)
delay = 10000
-- Display counter every so many iterations
display_every = 10

mac_to_name = {}

function make_macs(mac_list)
   local t = {}
   for _,defn in ipairs(mac_list) do
      local name, mac, when = unpack(defn)
      t[name] = { name=name, mac=mac, when=when or times}
      mac_to_name[mac]=name
   end
   return t;
end

-- Wired macs for hosts
ether=make_macs {
   { 'chunga',    '00:22:15:8c:bd:ac',  20 },
   { 'frog',      '00:16:d4:8f:f9:3f',  20 },
   { 'wombat',    '00:26:9e:5e:11:23',  20 },
   { 'lowrider',  '1c:af:f7:6b:ff:07',  20 },
   { 'onion',     '00:30:1b:48:c2:db',  20 },
   { 'radish',    '80:ee:73:13:ba:23',  20 },
   { 'puffin',    '88:ae:1d:51:62:69',  20 },
   { 'turnip',    '00:18:f3:99:34:1b',  20 },
   { 'pianobar',  '70:54:d2:18:7d:b3',  20 }
}

-- WIFI macs for hosts and dongles
radio = make_macs {
   { 'edimax1',   '00:1f:1f:01:f3:86' },
   { 'edimax2',   '00:1f:1f:01:f1:5c' },
   { 'chunga',    '00:15:af:ef:79:a4' },
   { 'frog',      '00:16:e3:c7:e0:71' },
   { 'wombat',    '00:1e:65:91:79:4a' },
   { 'lowrider',  '00:16:44:18:c8:de' },
   { 'puffin',    '70:f1:a1:f9:00:c6' }
}

-- Ping these no matter what the leases file says
ping_hosts = { 'lowrider', 'onion', 'radish', 'turnip', 'pianobar',
	      'chunga', 'frog', 'puffin', 'wombat', 'roadie' }

-- We can wake machines by class
class = {
   desktops = { 'shuttles', 'turnip', 'lowrider', 'pianobar' },
   bits32 = { 'frog', 'chunga' },
   bits64 = { 'desktops', 'puffin', 'wombat' },
   shuttles = { 'onion', 'radish' },
   laptops = { 'wombat', 'puffin', 'frog' },
   netbooks = { 'chunga' },
   amd = { 'puffin', 'lowrider' },
   intel = { 'onion', 'radish', 'turnip', 'wombat', 'frog', 'chunga',
	     'pianobar' },
   all = { 'intel', 'amd' }
}

function wake(ethers)
   local names = {}
   for _, ether in ipairs(ethers) do table.insert(names, ether.name) end
   io.write('Waking: '..table.concat(names, ', ')..'\n')
   local count=1
   local wakelan_cmd = { '/bin/wakelan', '-b', '172.20.0.255', '-m' }
   for time = 0,times - 1 do
      if time % display_every == 0 then
	 io.write((''..count)..'...')
	 count = count + 1
      end
      for _, victim in ipairs(ethers) do
	 if time % victim.when == 0 then
	    wakelan_cmd[5] = victim.mac
	    spawn.spawn('/bin/wakelan', wakelan_cmd)
	    spawn.wait()
	 end
      end
      spawn.usleep(delay)
      io.write '\r'
      io.flush()
   end
   io.write 'DONE!\n'
end

function resolve_ethers(names)
   local seen = {}
   local ethers = {}
   function resolve(name_list)
      for _, name in ipairs(name_list) do
	 if not seen[name] then
	    if ether[name] then
	       table.insert(ethers, ether[name])
	    elseif class[name] then
	       resolve(class[name])
	    else
	       io.write('Unknown machine: '..name..'\n')
	       os.exit(1)
	    end
	    seen[name] = true
	 end
      end
   end
   resolve(names)
   return ethers
end

function report_awake()
   local leases = {}
   local lease_file = io.open('/var/state/dnsmasq/dnsmasq.leases', 'r')
   for lease in lease_file:lines() do
      ether,ipaddr,name = lease:match "^.* (.*) (.*) (.*) .*"
      leases[ipaddr] = { mac=ether, ipaddr=ipaddr, name = name }
   end
   lease_file:close()
   io.write 'Hosts up:\n'
   local ping_jobs = {}
   local function ping_it(host, is_lease)
      local ping_cmd = { "/bin/ping", "-q", "-w3" }
      ping_cmd[4] = host
      local job = spawn.spawn("/bin/ping", ping_cmd, true)
      if job < 0 then error "Can't spawn" end
      ping_jobs[job] = { host=host, is_lease=is_lease }
      return job
   end
   for _, host in ipairs(ping_hosts) do job = ping_it(host, false) end
   for ipaddr,v in pairs(leases) do job = ping_it(ipaddr, true) end
   local anons, named = {}, {}
   local job, reason, value = spawn.wait()
   while job do
      if value == 0 then
	 local awake, host = ping_jobs[job], ping_jobs[job].host
	 if awake.is_lease then
	    local lease = leases[host]
	    if lease.name == '*' then
	       table.insert(anons, { name=mac_to_name[lease.mac] or lease.mac,
				     ip=host } )
	    else
	       named[lease.name] = mac_to_name[lease.mac]
	    end
	 elseif not named[host] then named[host] = false
	 end
      end
      job, reason, value = spawn.wait()
   end
   for host,real in pairs(named) do
      io.write('  '..host..
		  (real and (real ~= host) and ' ('..real..')' or '')..'\n')
   end
   for _,host in ipairs(anons) do
      io.write('  '..host.name..' @ '..host.ip..'\n')
   end
end

function split(str)
   local lst = {}
   local function split_aux(str)
      local token,rest = str:match '^%s*([^%s]+)(.*)$'
      if token then
	 table.insert(lst, token)
	 split_aux(rest)
      end
   end
   split_aux(str)
   return lst
end

if #arg > 0 then
   wake(resolve_ethers(arg[1] == '-c' and split(arg[2]) or arg))
else
   report_awake()
end
