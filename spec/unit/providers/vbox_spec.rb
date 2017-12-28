require 'spec_helper'
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

describe 'Vmpooler::PoolManager::Provider::VirtualBox' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:poolname) { '/MzGroup1'}
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
    port: 18083
    connection_pool_timeout: 1
    datacenter: MockDC
:pools:
  - name: '#{poolname}'
    alias: [ 'mockpool' ]
    template: 'centos7'
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
      Vmpooler::PoolManager::Provider::VirtualBox.new(config, logger, metrics, 'virtualbox', provider_options)
    end
  end

  # before(:each) do
    # allow(subject).to receive(:vbox_connection_ok?).and_return(true)
  # end

  describe '#name' do
    it 'should be virtualbox' do
      expect(subject.name).to eq('virtualbox')
    end
  end

  describe '#vms_in_pool' do

    context 'Given a pool folder with many VMs' do
      let(:expected_vm_list) {[
        {'name'=>'mz_logstash_ls5_1505846658855_51277'}
      ]}

      it 'should list all VMs in the VM folder for the pool' do

        VCR.use_cassette("vms") do
          result = subject.vms_in_pool('/MzGroup1')
          expect(result).to eq(expected_vm_list)
        end

      end
    end
  end

  describe '#get_vm_host' do

    context 'when VM exists and is running on a host' do

      hostname = 'mz_logstash_ls5_1505846658855_51277'
      it 'should return the hostname' do
        VCR.use_cassette("get_vm") do
          result = subject.get_vm('/MzGroup1', hostname)
          expect(result['name']).to eq(hostname)
        end
      end
    end

  end

  describe '#create_vm' do

    it 'should return a hash' do
      VCR.use_cassette("create_vm1") do
        result = subject.create_vm('/MzGroup1', 'testvm1')

        expect(result.is_a?(Hash)).to be true
      end
    end

    it 'should have the new VM name' do
      VCR.use_cassette("create_vm2") do
        result = subject.create_vm('/MzGroup1', 'testvm2')

        expect(result['name']).to eq('testvm2')
      end
    end

    it 'should raise an error' do
      VCR.use_cassette("create_vm_no_pool") do
        expect{ subject.create_vm('missing_pool', 'nonesuch') }.to raise_error(/missing_pool does not exist/)
      end
    end
  end

  describe '#destroy_vm' do

      it 'should delete VM by name' do
      VCR.use_cassette("destroy_vm") do
        result = subject.destroy_vm('', 'centos7 Clone')

        expect(result).to eq(false)
      end

    end

  end
end
