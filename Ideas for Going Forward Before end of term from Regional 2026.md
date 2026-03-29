# Team Composition

4 on hardware and 4 focused on business  
Hardware team  
They split up the firewalls, windows and linux servers  
Business Team  
(all help with injects)  
1 inject captain(make sure everything is done)  
1 inject team member(focus on knowing random services that are common)  
1 IR person  
1 Siem Person

# CLI Script Tool

The key here is the BASH cli will just make it faster to do things.  
I want everything in a function and all functions should have a easy undo and good help  
Then we can have a bunch of those and it the github we can have a custom call to do a bunch of them at once.  
The functions should be turning off cockpit, ssh, setting up local firewall, installing useful packages, windows read/fix services, fix some common reg keys, installing a service like xampp/firefox, installing the anit malware like malwarebytes or similar one we decide on  
Make sure to backup common binaries and install stuff in github  
Have a passwd so if corrupted they do not have passwords  
**Must work on windows or linux, idea is just quick git clone then have script**  
**Every command has an undo**

# Siem setup

Tied to CLI tool for setup  
Need something like pulsebeat(like zeek), suricata this is good at getting dns stuff and more information  
Wazuh and Splunk

# Something things to train on next year

Firewall  
Network on same stuff no vlan  
C2  
Ipv6 setup  
LibreNMS  
WAF  
NTP setup