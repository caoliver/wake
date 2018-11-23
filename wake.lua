#!/usr/local/bin/luajit
spawn = require 'spawn'

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
   { 'wombat',    '00:26:9e:5e:11:23',  20 },
   { 'lowrider',  '80:ee:73:13:ba:23',  20 },
   { 'onion',     '90:b1:1c:75:74:fb',  20 },
   { 'radish',    '90:b1:1c:87:4f:07',  20 },
   { 'puffin',    '88:ae:1d:51:62:69',  20 },
   { 'parsnip',   '70:54:d2:18:7d:b3',  20 },
}

-- WIFI macs for hosts and dongles
radio = make_macs {
   { 'edimax1',   '00:1f:1f:01:f3:86' },
   { 'edimax2',   '00:1f:1f:01:f1:5c' },
   { 'chunga',    '00:15:af:ef:79:a4' },
   { 'wombat',    '00:1e:65:91:79:4a' },
   { 'puffin',    '70:f1:a1:f9:00:c6' },
   { 'squirt',    'b8:27:eb:ca:b9:86' },
   { 'chopper',   'b8:27:eb:35:8e:0b' }
}

-- Ping these no matter what the leases file says
ping_hosts = { lowrider=1 , onion=1, radish=1, parsnip=1,
	      chunga=1, puffin=1, wombat=1, squirt=1, chopper=1,
	      --[[ roadie=1 --]] }

-- We can wake machines by class
class = {
   rpi = { 'squirt', 'chopper' },
   bits32 = { 'chunga' },
   bits64 = { 'parsnip', 'radish', 'onion', 'puffin', 'wombat',
              'lowrider' },
   music = { 'parsnip', 'radish', 'onion', 'puffin', 'wombat' },
   all = { 'bits64', 'bits32' }
}

function wake(ethers)
   local names = {}
   for _, ether in ipairs(ethers) do table.insert(names, ether.name) end
   table.sort(names)
   io.write('Waking: ',table.concat(names, ', '),'\n')
   local count=1
   local wakelan_cmd = { '/usr/local/libexec/wakelan',
			 '-b', '172.20.0.255', '-m' }
   for time = 0,times - 1 do
      if time % display_every == 0 then
	 io.write(count,'...')
	 count = count + 1
      end
      for _, victim in ipairs(ethers) do
	 if time % victim.when == 0 then
	    wakelan_cmd[5] = victim.mac
	    spawn.spawn('/usr/local/libexec/wakelan', wakelan_cmd)
	    spawn.wait()
	 end
      end
      spawn.usleep(delay)
      io.write '\r'
      io.flush()
   end
   io.write 'DONE!\n'
end

function resolve_classes(names)
   local seen = {}
   local result = {}
   function resolve(name_list)
      for _, name in ipairs(name_list) do
	 if not seen[name] then
	    seen[name] = true
	    if class[name] then
	       resolve(class[name])
	    else
	       result[name]=true
	    end
	 end
      end
   end
   resolve(names)
   return result
end

function resolve_ethers(names)
   local ethers = {}
   for name, _ in pairs(resolve_classes(names)) do
      if ether[name] then
	 table.insert(ethers, ether[name])
      else
	 io.write('Unknown machine: ',name,'\n')
	 os.exit(1)
      end
   end
   return ethers
end

function report_awake(filter)
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
   end
   if not filter then
      for host, _ in pairs(ping_hosts) do ping_it(host, false) end
      for ipaddr,v in pairs(leases) do ping_it(ipaddr, true) end
   else
      for name, _ in pairs(filter) do
	 if not ping_hosts[name] then
	    io.write('Unknown machine: ',name,'\n')
	    os.exit(1)
	 end
      end
      for host, _ in pairs(filter) do ping_it(host, false) end
   end
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
	       named[lease.name] = mac_to_name[lease.mac] or
		  lease.mac..' @ '..host
	    end
	 elseif not named[host] then named[host] = false
	 end
      end
      job, reason, value = spawn.wait()
   end
   for host,real in pairs(named) do
      io.write('  ',host,
		  (real and (real ~= host) and ' ('..real..')' or ''),'\n')
   end
   for _,host in ipairs(anons) do
      io.write('  ',host.name,' @ ',host.ip,'\n')
   end
end

function show_candidates()
   for name,_ in pairs(ether) do
      print(name)
   end
   print "----"
   for name,_ in pairs(class) do
      print(name)
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
   local requests=arg[1] == '-c' and split(arg[2]) or arg
   if requests[1] == '//' then
      show_candidates()
   elseif requests[1] == '/' then
      table.remove(requests,1)
      report_awake(#requests > 0 and resolve_classes(requests))
   else
      wake(resolve_ethers(requests))
   end
else
   report_awake()
end
