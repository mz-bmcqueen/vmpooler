# require 'virtualbox-ws'

module Vmpooler
  class PoolManager
    class Provider
      class VirtualBox < Vmpooler::PoolManager::Provider::Base

        attr_reader :connection_pool
        
        # how to do class vars in ruby? these need to be initialized
        # and the vbox config above too
        # probably not using attr_reader
        # something like this
        # don't know if configure returns anything useful or neccessary
        #  but it needs to be run once per class

        # !!dont use @@ class vars 
        # the community hates it
        # !!there's another way to do this which is standard
        #https://www.ruby-forum.com/topic/809975

        # require 'virtualbox-ws'

        # @web_session_mgr = VBox::WebsessionManager.new
        # @virtual_box = @web_session_mgr.logon

        # class << self
          attr_accessor :web_session_mgr
          attr_accessor :virtual_box
        # end

        def initialize(config, logger, metrics, name, options)
          super(config, logger, metrics, name, options)

          VBox::WebService.configure do |vbconfig|
            vbconfig.vboxweb_host = provider_config()['server'] || '127.0.0.1'
            vbconfig.vboxweb_port = provider_config()['port'] || '18083'
            vbconfig.vboxweb_user = provider_config()['username']
            vbconfig.vboxweb_pass = provider_config()['password']
            vbconfig.log_level = provider_config()['VBOXWEB_LOGGING'] || 'ERROR'
            # config.vboxweb_host = '127.0.0.1'
            # config.vboxweb_port = '18083'
            # config.log_level = 'ERROR'
          end

          @web_session_mgr = VBox::WebsessionManager.new
          @virtual_box = @web_session_mgr.logon

          task_limit = global_config[:config].nil? || global_config[:config]['task_limit'].nil? ? 10 : global_config[:config]['task_limit'].to_i

          default_connpool_size = [provided_pools.count, task_limit, 2].max
          connpool_size = provider_config['connection_pool_size'].nil? ? default_connpool_size : provider_config['connection_pool_size'].to_i
          # The default connection pool timeout should be quite large - 60 seconds
          connpool_timeout = provider_config['connection_pool_timeout'].nil? ? 60 : provider_config['connection_pool_timeout'].to_i
          logger.log('d', "[#{name}] ConnPool - Creating a connection pool of size #{connpool_size} with timeout #{connpool_timeout}")
          @connection_pool = Vmpooler::PoolManager::GenericConnectionPool.new(
            metrics: metrics,
            metric_prefix: "#{name}_provider_connection_pool",
            size: connpool_size,
            timeout: connpool_timeout
          ) do
            logger.log('d', "[#{name}] Connection Pool - Creating a connection object")

            new_conn = web_session.get_session_object
            { connection: new_conn }
          end

        end

        # name of the provider class
        # def name
          # 'virtualbox'
        # end

        #redo this using a connection from the pool
        #seems to be called like this: vsphere_connection_ok?(connection_pool_object[:connection])
        #so its got a web_session session object
        #so whatever can be sent to a session
        def vbox_connection_ok?(connection)
          # VBox::WebService.connect
          return true
        rescue
          return false
        end

        # inputs
        #  [String] pool_name : Name of the pool
        # returns
        #   Array[Hashtable]
        #     Hash contains:
        #       'name' => [String] Name of VM
        def vms_in_pool(_pool_name)

          return @virtual_box.get_machines_by_groups({ :groups => [_pool_name] }).select do | machine |
            begin
              machine.name
            rescue
              $logger.log('s', "[x] skipping bad vm [#{_pool_name}] '#{machine}'")
              next
            end
          end.map do | machine |
            { "name" => machine.name }
          end

        end

        # inputs
        #   [String]pool_name : Name of the pool
        #   [String] vm_name  : Name of the VM
        # returns
        #   [String] : Name of the host computer running the vm.  If this is not a Virtual Machine, it returns the vm_name
        def get_vm_host(_pool_name, _vm_name)

          #for v1 virtualbox support this is all local so the hostname will always be localhost
          return 'localhost'
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM
        # returns
        #   [String] : Name of the most appropriate host computer to run this VM.  Useful for load balancing VMs in a cluster
        #                If this is not a Virtual Machine, it returns the vm_name
        def find_least_used_compatible_host(_pool_name, _vm_name)
          #for v1 virtualbox support this is all local so the hostname will always be localhost
          return 'localhost'
        end

        # inputs
        #   [String] pool_name      : Name of the pool
        #   [String] vm_name        : Name of the VM to migrate
        #   [String] dest_host_name : Name of the host to migrate `vm_name` to
        # returns
        #   [Boolean] : true on success or false on failure
        def migrate_vm_to_host(_pool_name, _vm_name, _dest_host_name)

          #v1 virtualbox support is all localhost so this is an exception
          raise("#{self.class.name} does not implement migrate_vm_to_host")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to find
        # returns
        #   nil if VM doesn't exist
        #   [Hastable] of the VM
        #    [String] name       : Name of the VM
        #    [String] hostname   : Name reported by Vmware tools (host.summary.guest.hostName)
        #    [String] template   : This is the name of template exposed by the API.  It must _match_ the poolname
        #    [String] poolname   : Name of the pool the VM is located
        #    [Time]   boottime   : Time when the VM was created/booted
        #    [String] powerstate : Current power state of a VM.  Valid values (as per vCenter API)
        #                            - 'PoweredOn','PoweredOff'
        def get_vm(_pool_name, _vm_name)
          # raise("#{self.class.name} does not implement get_vm")

          return @virtual_box.get_machines_by_groups({ :groups => [_pool_name] }).select do | machine |
            begin
              machine.name
            rescue
              $logger.log('s', "[x] skipping bad vm [#{_pool_name}] '#{machine}'")
              next
            end
          end.map do | machine |
            { 
              'name' => machine.name,
              'hostname' => 'localhost',
              'template' => _pool_name,
              'poolname' => _pool_name,
              'boottime' => Time.new,
              'powerstate' => machine.state, 
            }
          end.first
        end

        # inputs
        #   [String] pool       : Name of the pool
        #   [String] new_vmname : Name to give the new VM
        # returns
        #   [Hashtable] of the VM as per get_vm
        #   Raises RuntimeError if the pool_name is not supported by the Provider
        def create_vm(_pool_name, _new_vmname)

          my_pool_config = pool_config(_pool_name)
          raise("Pool #{_pool_name} does not exist for the provider #{name}") if my_pool_config.nil?

          source_machine = virtual_box.find_machine(:nameOrId => my_pool_config['template'])
          raise("Template #{_pool_name} does not exist for the provider #{name}") if source_machine.nil?

          new_machine = virtual_box.create_machine(:name => _new_vmname, :os_type_id => 'Other', :groups => _pool_name)

          clone_progress = source_machine.clone_to(:target => new_machine, :mode => 2)

          clone_progress.wait_for_completion(:timeout => -1)
          virtual_box.register_machine(:machine => new_machine)

          # Start the VM
          sess = @web_session_mgr.get_session_object
          launch_progress = new_machine.launch_vm_process(:session => sess)

          launch_progress.wait_for_completion(:timeout => -1)

          sess.unlock_machine()

          return { 
              'name' => _new_vmname,
              'hostname' => new_machine.name,
              'template' => pool_config(_pool_name)['template'],
              'poolname' => _pool_name,
              'boottime' => Time.new,
              'powerstate' => new_machine.state, 
            }
        end

        # inputs
        #   [String]  pool_name  : Name of the pool
        #   [String]  vm_name    : Name of the VM to create the disk on
        #   [Integer] disk_size  : Size of the disk to create in Gigabytes (GB)
        # returns
        #   [Boolean] : true if success, false if disk could not be created
        #   Raises RuntimeError if the Pool does not exist
        #   Raises RuntimeError if the VM does not exist
        def create_disk(_pool_name, _vm_name, _disk_size)
          raise("#{self.class.name} does not implement create_disk")
        end

        # inputs
        #   [String] pool_name         : Name of the pool
        #   [String] new_vmname        : Name of the VM to create the snapshot on
        #   [String] new_snapshot_name : Name of the new snapshot to create
        # returns
        #   [Boolean] : true if success, false if snapshot could not be created
        #   Raises RuntimeError if the Pool does not exist
        #   Raises RuntimeError if the VM does not exist
        def create_snapshot(_pool_name, _vm_name, _new_snapshot_name)
          raise("#{self.class.name} does not implement create_snapshot")
        end

        # inputs
        #   [String] pool_name     : Name of the pool
        #   [String] new_vmname    : Name of the VM to restore
        #   [String] snapshot_name : Name of the snapshot to restore to
        # returns
        #   [Boolean] : true if success, false if snapshot could not be revertted
        #   Raises RuntimeError if the Pool does not exist
        #   Raises RuntimeError if the VM does not exist
        #   Raises RuntimeError if the snapshot does not exist
        def revert_snapshot(_pool_name, _vm_name, _snapshot_name)
          raise("#{self.class.name} does not implement revert_snapshot")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to destroy
        # returns
        #   [Boolean] : true if success, false on error. Should returns true if the VM is missing
        def destroy_vm(_pool_name, _vm_name)

          machine = virtual_box.find_machine(:nameOrId => _vm_name)
          return true if machine.nil?
          
          sess = @web_session_mgr.get_session_object
          begin
            machine.lock_machine(:session => sess, :lockType => 'VM')
            progress = sess.console.power_down()
            progress.wait_for_completion(:timeout => -1)
          rescue Exception => e
            $logger.log('s', "[x] can't destroy vm: can't get lock [#{_pool_name}] '#{machine}'. #{e.message}")
            return false
          end

          begin
            machine.unregister(:cleanupMode => 'Full')
          rescue Exception => e
            $logger.log('s', "[x] can't unregister vm: can't get lock [#{_pool_name}] '#{machine}'. #{e.message}")
            return false
          end

          return true

        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to check if ready
        # returns
        #   [Boolean] : true if ready, false if not
        def vm_ready?(_pool_name, _vm_name)
          raise("#{self.class.name} does not implement vm_ready?")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to check if it exists
        # returns
        #   [Boolean] : true if it exists, false if not
        def vm_exists?(pool_name, vm_name)
          !get_vm(pool_name, vm_name).nil?
        end
      end
    end
  end
end
