require 'spec_helper'
require 'rack/test'
require 'bosh/director/api/controllers/configs_controller'

module Bosh::Director
  describe Api::Controllers::ConfigsController do
    include Rack::Test::Methods

    subject(:app) { Api::Controllers::ConfigsController.new(config) }
    let(:config) do
      config = Config.load_hash(SpecHelper.spec_get_director_config)
      identity_provider = Support::TestIdentityProvider.new(config.get_uuid_provider)
      allow(config).to receive(:identity_provider).and_return(identity_provider)
      config
    end

    describe 'GET', '/' do
      context 'with authenticated admin user' do
        before(:each) do
          authorize('admin', 'admin')
        end

        it 'return the config' do
          Models::Config.make(
            content: 'some-yaml',
            created_at: Time.now - 3.days
          )

          newest_config = 'new_config'
          Models::Config.make(
            content: newest_config,
            created_at: Time.now - 1
          )

          get '/my-type?name=some-name'

          expect(last_response.status).to eq(200)
          expect(JSON.parse(last_response.body)['content']).to eq(newest_config)
        end

        context 'when name is missing from the params' do
          before do
            Models::Config.make(
                name: 'with-some-name',
                content: 'some_config'
            )

            Models::Config.make(
                name: '',
                content: 'config-with-empty-name'
            )
          end

          it 'uses the default name' do
            get '/my-type'

            expect(last_response.status).to eq(200)
            expect(JSON.parse(last_response.body)['content']).to eq('config-with-empty-name')
          end
        end

        context "when 'type' is not specified" do
          it 'returns STATUS 404' do
            get '/?name=some-name'

            expect(last_response.status).to eq(404)
          end
        end
      end

      context 'without an authenticated user' do
        it 'denies access' do
          expect(get('/my-type').status).to eq(401)
        end
      end

      context 'when user is reader' do
        before { basic_authorize('reader', 'reader') }

        it 'permits access' do
          expect(get('/my-type').status).to eq(200)
        end
      end
    end

    describe 'POST', '/:type' do
      let(:content) { YAML.dump(Bosh::Spec::Deployments.simple_runtime_config) }

      describe 'when user has admin access' do
        before { authorize('admin', 'admin') }

        it 'creates a new config' do
          expect {
            post '/my-type', content, {'CONTENT_TYPE' => 'text/yaml'}
          }.to change(Bosh::Director::Models::Config, :count).from(0).to(1)

          expect(last_response.status).to eq(201)
          expect(Bosh::Director::Models::Config.first.content).to eq(content)
        end

        it 'creates new config and does not update existing ' do
          post '/my-type', content, {'CONTENT_TYPE' => 'text/yaml'}
          expect(last_response.status).to eq(201)

          expect {
            post '/my-type', content, {'CONTENT_TYPE' => 'text/yaml'}
          }.to change(Bosh::Director::Models::Config, :count).from(1).to(2)

          expect(last_response.status).to eq(201)
          expect(Bosh::Director::Models::Config.last.content).to eq(content)
        end

        it 'gives a nice error when request body is not a valid yml' do
          post '/my-type', "}}}i'm not really yaml, hah!", {'CONTENT_TYPE' => 'text/yaml'}

          expect(last_response.status).to eq(400)
          expect(JSON.parse(last_response.body)['code']).to eq(440001)
          expect(JSON.parse(last_response.body)['description']).to include('Incorrect YAML structure of the uploaded manifest: ')
        end

        it 'gives a nice error when request body is empty' do
          post '/my-type', '', {'CONTENT_TYPE' => 'text/yaml'}

          expect(last_response.status).to eq(400)
          expect(JSON.parse(last_response.body)).to eq(
              'code' => 440001,
              'description' => 'Manifest should not be empty',
          )
        end

        it 'creates a new event' do
          expect {
            post '/my-type', content, {'CONTENT_TYPE' => 'text/yaml'}
          }.to change(Bosh::Director::Models::Event, :count).from(0).to(1)
          event = Bosh::Director::Models::Event.first
          expect(event.object_type).to eq('config')
          expect(event.object_name).to eq('')
          expect(event.action).to eq('create')
          expect(event.user).to eq('admin')
        end

        it 'creates a new event with error' do
          expect {
            post '/my-type', {}, {'CONTENT_TYPE' => 'text/yaml'}
          }.to change(Bosh::Director::Models::Event, :count).from(0).to(1)
          event = Bosh::Director::Models::Event.first
          expect(event.object_type).to eq('config')
          expect(event.object_name).to eq('')
          expect(event.action).to eq('create')
          expect(event.user).to eq('admin')
          expect(event.error).to eq('Manifest should not be empty')
        end

        context 'when a name is passed in via a query param' do
          let(:path) { '/my-type?name=smurf' }

          it 'creates a new named config' do
            post path, content, {'CONTENT_TYPE' => 'text/yaml'}

            expect(last_response.status).to eq(201)
            expect(Bosh::Director::Models::Config.first.name).to eq('smurf')
          end

          it 'creates a new event and add name to event context' do
            expect {
              post path, content, {'CONTENT_TYPE' => 'text/yaml'}
            }.to change(Bosh::Director::Models::Event, :count).from(0).to(1)

            event = Bosh::Director::Models::Event.first
            expect(event.object_type).to eq('config')
            expect(event.object_name).to eq('smurf')
            expect(event.action).to eq('create')
            expect(event.user).to eq('admin')
          end
        end
      end

      describe 'when user has readonly access' do
        before { basic_authorize 'reader', 'reader' }

        it 'denies access' do
          expect(post('/my-type', content, {'CONTENT_TYPE' => 'text/yaml'}).status).to eq(401)
        end
      end
    end
  end
end
