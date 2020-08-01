#!/usr/bin/env python
import telnetlib
import logging
import time
import re
import os
import configparser
from pyVim import connect
from pyVmomi import vim

def logger_create():
    logname = 'shutdownlog_' + time.strftime('%Y-%m-%d_%H-%M-%S') + '.log'
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    logfile = logging.FileHandler(logname)
    fmt = '%(asctime)s - %(message)s'
    
    formatter = logging.Formatter(fmt)
    logfile.setFormatter(formatter)
    logger.addHandler(logfile)
    return logger
    
logger = logger_create()

def read_config():
    try:
        config = configparser.ConfigParser(allow_no_value=True)
        config_path = os.path.join(os.path.dirname(__file__), 'config.txt')
        with open(config_path) as f:
            config.read_file(f)
        logger.info('Successfully opened config file')
    except FileNotFoundError:
        logger.critical('Config file with name "config.txt" not found')
        quit()
    except:
        logger.critical('Failed to parse config file')
        quit()
    return config

def vcenter_connect(config):
    try:
        connection = connect.SmartConnectNoSSL(**config['VSphere'])
        logger.info('Successfully connected to VCenter')
    except vim.fault.InvalidLogin:
        logger.critical('Failed to connect to VCenter: incorrect user name or password')
        quit()
    except:
        logger.critical('Failed to connect to VCenter')
        quit()
    return connection

def host_connect(config, hostname):
    try:
        connection = connect.SmartConnectNoSSL(**config[hostname])
        logger.info('Successfully connected to host %s' % hostname)
    except vim.fault.InvalidLogin:
        logger.error('Failed to connect to %s: incorrect user name or password' % hostname)
    except:
        logger.error('Failed to connect to %s')
    try:
        content = connection.RetrieveServiceContent()
        host = content.viewManager.CreateContainerView(content.rootFolder, [vim.HostSystem], True)
        [host] = host.view
    except:
        logger.error('Failed to retrieve ESXi data from %s' % host.name)
    return host

def get_all_vms(connection):  
    try:
        vmlist = {}
        content = connection.RetrieveContent()
        container = content.viewManager.CreateContainerView(content.rootFolder, [vim.VirtualMachine], True)
        for vm in container.view:
            vmlist[vm.name] = vm
        logger.info('Successfully retieved list of VMs')
    except:
        logger.error('Failed to retrieve list of VMs')
    return vmlist

def get_cluster_vms(connection, config):
    try:
        content = connection.RetrieveContent()
        children = content.rootFolder.childEntity
        vmlist = {}
        hostlist = {}
        for dc in children:
            if config['Namings']['datacentername'] == dc.name:
                clusters = dc.hostFolder.childEntity
                for cluster in clusters:
                    if config['Namings']['clustername'] == cluster.name:
                        hosts = cluster.host                   
                        for host in hosts:
                            hostlist[host.name] = host
                            vms = host.vm
                            for vm in vms:
                                vmlist[vm.name] = vm
        logger.info('Successfully retieved list of VMs')
    except:
        logger.error('Failed to retrieve list of vms')
    return vmlist, hostlist
    
def vm_shutdown(vmlist, vmname):
    try:
        vmlist[vmname].ShutdownGuest()
        logger.info('Shutting down VM %s' % vmname)
    except KeyError:
        logger.warning('VM with name %s not found' % vmname)    
    except vim.fault.ToolsUnavailable:
        try:
            logger.warning('VM %s no tools, powering off' % vmname)
            vmlist[vmname].PowerOff()
        except:
            logger.error('Failed to power off VM %s' % vmname)
    except vim.fault.TaskInProgress:
        try:
            logger.warning('VM %s currently has task in progress, powering off' % vmname)
            vmlist[vmname].PowerOff()
        except:
            logger.error('Failed to power off VM %s' % vmname)
    except vim.fault.InvalidPowerState:
        logger.info('VM %s is already powered off' % vmname)
    except Exception as e:
        logger.error('Failed to shutdown VM %s' % vmname)
        print(e)

def vm_shutdown_first(vmlist, shutdownlastlist):
    for vm in vmlist:
        if vmlist[vm].name not in shutdownlastlist:
            vm_shutdown(vmlist, vmlist[vm].name)

def vm_shutdown_last(vmlist, shutdownlastlist, config):
    for vm in vmlist:
        if vmlist[vm].name in shutdownlastlist and vmlist[vm].name != config['ShutdownLast']['vcentervm']:
            vm_shutdown(vmlist, vmlist[vm].name)
    if config['Parameters']['shutdownvcenter'] == 'True':
        logger.info('Shutting down VCenter')
        vm_shutdown(vmlist, config['ShutdownLast']['vcentervm'])
def sw_maintenance(config):
    host = config['StarWind']['host'].encode()
    port = config['StarWind']['port'].encode()
    swlogin = config['StarWind']['swlogin'].encode()
    swpass = config['StarWind']['swpass'].encode()
    
    telnet = telnetlib.Telnet()
    
    try:
        telnet.open(host, port)
    except:
        logger.error('failed to connect')
    else:
        with telnet:
            telnet.write(b'protocolversion 100\n')
            telnet.write(b'login %s %s\n' % (swlogin, swpass))
            telnet.write(b'list -what:"devices"\n')
            time.sleep(5)
            output = telnet.read_very_eager().decode('UTF-8')
            devicelist = re.finditer(r'DeviceId="(0x[0-9A-F]{16})"', output)
            
            logger.info('Turning on maintenance mode for all StarWind devices')
            
            for d in devicelist:
                telnet.write(b'control %s -SwitchMaintenanceMode:"1" -force:"yes"\n' % d.group(1).encode())
                time.sleep(2)

def host_maintenance(host):
    try:
        host.EnterMaintenanceMode(0)
        logger.info('Host %s entering maintenance mode' % host.name)
    except InvalidState:
        logger.warning('Host %s already in maintanance mode' % host.name)
    except:
        logger.error('Host %s failed to enter maintenance mode' % host.name)

def host_shutdown(host):
    try:
        host.ShutdownHost_Task(force=True)
        logger.info('Host %s is shutting down' % host.name)
    except:
        logger.error('Host %s failed to shutdown' % host.name)

def main():
    config = read_config()
    connection = vcenter_connect(config)
    shutdownlastlist = [config['ShutdownLast'][vm] for vm in config['ShutdownLast']]
        
    if config['Parameters']['shutdownclustervmsonly'] == 'True':
        vmlist, hostlist = get_cluster_vms(connection, config)
    else:
        vmlist = get_all_vms(connection)

    logger.info('Shutting down all VMs except StarWind')
    vm_shutdown_first(vmlist, shutdownlastlist)
    time.sleep(90)
    logger.info('Trying to power off VMs that are taking too long to shutdown or stuck')
    vm_shutdown_first(vmlist, shutdownlastlist)
    time.sleep(10)
    sw_maintenance(config)
    logger.info('Shutting down all VMs that are left')
    vm_shutdown_last(vmlist, shutdownlastlist, config)
    time.sleep(120)
    host1 = host_connect(config, 'Host1')
    host2 = host_connect(config, 'Host2')
    host_maintenance(host1)
    host_maintenance(host2)
    time.sleep(10)
    host_shutdown(host1)
    time.sleep(30)
    host_shutdown(host2)
    
if __name__ == "__main__":
    main()