#!/usr/local/bin/luajit
ffi = require 'ffi'
ffi.cdef [[
    int wait(unsigned int *);
    int close(int);
    int fork();
    int execvp(const char *, const char *[]);
    void *signal(int, void *);
    int usleep(int);
    void perror(const char*);
]]

-- ignore sighup, sigint, sigquit, and sigtstp
ignore = ffi.cast('void *', 1)
ffi.C.signal(1, ignore)
ffi.C.signal(2, ignore)
ffi.C.signal(3, ignore)
ffi.C.signal(20, ignore)

function spawn(args, close_out)
   argv = ffi.new('const char *[?]', #args+1, args)
   argv[#args] = nil
   local process = ffi.C.fork()
   assert(process >= 0)
   if process > 0 then return process end
   if close_out then ffi.C.close(1) end
   ffi.C.execvp(argv[0], argv)
   os.exit(1)
end

function wait()
   local status = ffi.new 'unsigned int [1]'
   local process = ffi.C.wait(status)
   if process < 0 then return end
   local sigstate = status[0] % 128
   if  sigstate > 0 then
      return process, 'signal', sigstate
   else
      return process, 'exit', status[0]/256 % 256
   end
end

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
   { 'wombat',    '00:26:9e:5e:11:23',  20 },
   { 'lowrider',  '80:ee:73:13:ba:23',  20 },
   { 'onion',     '5c:f9:dd:75:9e:0d',  20 },
   { 'radish',    '90:b1:1c:87:4f:07',  20 },
   { 'puffin',    '88:ae:1d:51:62:69',  20 },
   { 'parsnip',   '70:54:d2:18:7d:b3',  20 },
   { 'retread',   '00:1a:a0:68:fa:22',  20 },
   { 'wormy',     '38:c9:86:5a:a9:bf',  20 },
   { 'barnacle',  'a0:b3:cc:7d:e2:c8',  20 },
   { 'lunchbox',  '00:25:64:9f:a3:e4',  20 },
   { 'toaster',   'd4:be:d9:c1:10:d3',  20 },
   { 'fluffy',    '00:30:1b:48:c2:db',  20 },
   { 'chunga',    '00:22:15:8c:bd:ac',  20 },
   { 'squirt',    'b8:27:eb:9f:ec:d3',  20 },
   { 'frobnitz',  'b8:27:eb:c1:be:49',  20 },
   { 'bagel',     'b8:27:eb:12:ec:8f',  20 },
}

-- WIFI macs for hosts and dongles
radio = make_macs {
   { 'edimax1',   '00:1f:1f:01:f3:86' },
   { 'edimax2',   '00:1f:1f:01:f1:5c' },
   { 'chunga',    '00:15:af:ef:79:a4' },
   { 'wombat',    '00:1e:65:91:79:4a' },
   { 'puffin',    '70:f1:a1:f9:00:c6' },
   { 'squirt',    'b8:27:eb:ca:b9:86' },
   { 'frobnitz',  'b8:27:eb:94:eb:1c' },
   { 'barnacle',  '20:10:7a:74:ce:88' },
}

-- Stuff that shouldn't appear
local no_show = {
  ['28:c6:8e:f4:85:97'] = true,
  ['b8:27:eb:84:29:82'] = true,
}

-- Ping these no matter what the leases file says
ping_hosts = { lowrider=1 , onion=1, radish=1, parsnip=1, retread=1, 
	      puffin=1, wombat=1, squirt=1, frobnitz=1, wormy=1, barnacle=1, 
	      lunchbox=1, toaster=1, chunga=1, fluffy=1, bagel=1,
	      --[[ roadie=1 --]] }

-- We can wake machines by class
class = {
   raspi = { 'squirt', 'frobnitz', 'bagel' },
   bits32 = { 'chunga' },
   bits64 = { 'parsnip', 'radish', 'onion', 'puffin', 'wombat', 'retread',
   	      'lowrider', 'barnacle', 'lunchbox', 'toaster', 'fluffy' },
   gig = { 'parsnip', 'radish', 'onion', 'wombat', 'retread',
	      'lowrider', 'lunchbox', 'toaster', 'fluffy' },
   apple = { 'wormy' },
   all = { 'bits64', 'bits32', 'apple', 'raspi' }
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
	    spawn(wakelan_cmd)
	    wait()
	 end
      end
      ffi.C.usleep(delay)
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
      if not no_show[ether] then
         leases[ipaddr] = { mac=ether, ipaddr=ipaddr, name = name }
      end
   end
   lease_file:close()
   io.write 'Hosts up:\n'
   local ping_jobs = {}
   local function ping_it(host, is_lease)
      local ping_cmd = { "/bin/ping", "-q", "-w2" }
      ping_cmd[4] = host
      local job = spawn(ping_cmd, true)
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
   local job, reason, value = wait()
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
      job, reason, value = wait()
   end
   for host,real in pairs(named) do
      io.write('  ',host,
		  (real and (real ~= host) and ' ('..real..')' or ''),'\n')
   end
   for _,host in ipairs(anons) do
      io.write('  ',host.name,' @ ',host.ip,'\n')
   end
end

function show_candidates(names)
   if names[1] then
      for name in pairs(resolve_classes(names)) do
	 if ether[name] then print(name) end
      end
      return
   end
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
      table.remove(requests,1)
      show_candidates(requests)
   elseif requests[1] == '/' then
      table.remove(requests,1)
      report_awake(#requests > 0 and resolve_classes(requests))
   else
      wake(resolve_ethers(requests))
   end
else
   report_awake()
end
