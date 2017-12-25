require 'spec_helper'
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

RSpec::Matchers.define :create_vm_spec do |new_name,target_folder_name,datastore|
  match { |actual|
    # Should have the correct new name
    actual[:name] == new_name &&
    # Should be in the new folder
    actual[:folder].name == target_folder_name &&
    # Should be poweredOn after clone
    actual[:spec].powerOn == true &&
    # Should be on the correct datastore
    actual[:spec][:location].datastore.name == datastore &&
    # Should contain annotation data
    actual[:spec][:config].annotation != '' &&
    # Should contain VIC information
    actual[:spec][:config].extraConfig[0][:key] == 'guestinfo.hostname' &&
    actual[:spec][:config].extraConfig[0][:value] == new_name
  }
end

describe 'Vmpooler::PoolManager::Provider::VirtualBox' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:poolname) { 'pool1'}
  let(:provider_options) { { 'param' => 'value' } }
  let(:datacenter_name) { 'MockDC' }
  let(:config) { YAML.load(<<-EOT
---
:config:
  max_tries: 3
  retry_factor: 10
:providers:
  :virtualbox:
    server: "localhost"
    username: "vbox_user"
    password: "vbox_password"
    port: 13013
    connection_pool_timeout: 1
    datacenter: MockDC
:pools:
  - name: '#{poolname}'
    alias: [ 'mockpool' ]
    template: 'Templates/pool1'
    size: 5
    timeout: 10
    ready_ttl: 1440
    clone_target: 'cluster1'
EOT
    )
  }

  let(:connection_options) {{}}
  # let(:connection) { mock_RbVmomi_VIM_Connection(connection_options) }
  # let(:vmname) { 'vm1' }

  subject do
    VCR.use_cassette("wsdl") do
      Vmpooler::PoolManager::Provider::VirtualBox.new(config, logger, metrics, 'vbox1', provider_options)
    end
  end

  # before(:each) do
    # allow(subject).to receive(:vbox_connection_ok?).and_return(true)
  # end

  describe '#name' do
    it 'should be vbox1' do
      expect(subject.name).to eq('vbox1')
    end
  end

  describe '#vms_in_pool' do

    context 'Given a pool folder with many VMs' do
      let(:expected_vm_list) {[
        { 'name' => 'vm1'},
        { 'name' => 'vm2'},
        { 'name' => 'vm3'}
      ]}

      it 'should list all VMs in the VM folder for the pool' do

        VCR.use_cassette("vms") do
          result = subject.vms_in_pool('mz')
          expect(result).to eq(expected_vm_list)
        end

      end
    end
  end
end
