require 'spec_helper'

describe Project do
  let(:project) { FactoryGirl.create(:jenkins_project) }

  describe "factories" do
    it "should be valid for project" do
      FactoryGirl.build(:project).should be_valid
    end
  end

  describe 'associations' do
    it { should have_many :statuses }
    it { should have_many :payload_log_entries  }
    it { should belong_to :aggregate_project }
    it { should belong_to(:creator).class_name("User") }
  end

  describe "validations" do
    it { should validate_presence_of :name }
    it { should validate_presence_of :type }
  end

  describe "callbacks" do
    let!(:count) {  ProjectMonitor::Application.config.max_status - 1 }

    before do
      project.statuses << FactoryGirl.create_list(:project_status, count, project: project)
    end
    context 'when the project is online' do
      let(:project) { FactoryGirl.build(:jenkins_project).tap {|p| p.online = true } }

      it 'should set the last_refreshed_at' do
        project.last_refreshed_at.should be_present
      end

      context 'removing an outdated status upon adding a new status' do
        context 'with less than 15 previous statuses' do
          it "should not delete any statuses from the project" do
            project.statuses.count.should ==  ProjectMonitor::Application.config.max_status - 1
          end
        end

        context 'when exactly 15 previous statuses' do
          let(:count) {  ProjectMonitor::Application.config.max_status }
          it "should not delete any statuses from the project" do
            project.statuses.count.should == ProjectMonitor::Application.config.max_status
          end
        end

        context 'when more than 15 previous statuses' do
          let(:count) {  ProjectMonitor::Application.config.max_status + 10 }
          it "should delete statuses from the project of statuses more than the max" do
            project.statuses.count.should == ProjectMonitor::Application.config.max_status
          end
        end
      end

      context 'when the project is offline' do
        let(:project) { FactoryGirl.build(:jenkins_project) }

        it 'should not set the last_refreshed_at' do
          project.last_refreshed_at.should be_nil
        end
      end
    end
  end

  describe 'scopes' do
    describe "standalone" do
      it "should return non aggregated projects" do
        Project.standalone.should include projects(:pivots)
        Project.standalone.should include projects(:socialitis)
        Project.standalone.should_not include projects(:internal_project1)
        Project.standalone.should_not include projects(:internal_project2)
      end
    end

    describe "enabled" do
      let!(:disabled_project) { FactoryGirl.create(:jenkins_project, enabled: false) }

      it "should return only enabled projects" do
        Project.enabled.should include projects(:pivots)
        Project.enabled.should include projects(:socialitis)

        Project.enabled.should_not include disabled_project
      end
    end

    describe "with_statuses" do
      it "returns projects only with statues" do
        projects = Project.with_statuses

        projects.length.should > 9
        projects.should_not include project
        projects.each do |project|
          project.latest_status.should_not be_nil
        end
      end
    end

    describe "with_aggregate_project" do
      subject do
        Project.with_aggregate_project(aggregate_projects(:internal_projects_aggregate)) do
          Project.all
        end
      end

      it { should include projects(:internal_project1) }
      it { should_not include projects(:socialitis) }
    end

    describe '.updateable' do
      subject { Project.updateable }

      let!(:enabled_webhooks_project) { FactoryGirl.create(:jenkins_project, enabled: true, webhooks_enabled: true) }
      let!(:disabled_webhooks_project) { FactoryGirl.create(:jenkins_project, enabled: false, webhooks_enabled: true) }
      let!(:disabled_polling_project) { FactoryGirl.create(:jenkins_project, enabled: false, webhooks_enabled: false) }
      let!(:enabled_polling_project) { FactoryGirl.create(:jenkins_project, enabled: true, webhooks_enabled: false) }
      let!(:enabled_nil_project) { FactoryGirl.create(:jenkins_project, enabled: true, webhooks_enabled: nil) }
      let!(:disabled_nil_project) { FactoryGirl.create(:jenkins_project, enabled: false, webhooks_enabled: nil) }

      it { should_not include enabled_webhooks_project }
      it { should_not include disabled_webhooks_project }
      it { should_not include disabled_polling_project }
      it { should include enabled_polling_project }
      it { should include enabled_nil_project }
      it { should_not include disabled_nil_project }
    end

    describe '.tracker_updateable' do
      subject { Project.tracker_updateable }

      let!(:updateable1) { FactoryGirl.create(:jenkins_project, tracker_auth_token: 'aafaf', tracker_project_id: '1') }
      let!(:updateable2) { FactoryGirl.create(:travis_project, tracker_auth_token: 'aafaf', tracker_project_id: '1') }
      let!(:not_updateable1) { FactoryGirl.create(:jenkins_project, tracker_project_id: '1') }
      let!(:not_updateable2) { FactoryGirl.create(:jenkins_project, tracker_auth_token: 'aafaf') }
      let!(:not_updateable3) { FactoryGirl.create(:travis_project, tracker_project_id: '', tracker_auth_token: '') }

      it { should include updateable1 }
      it { should include updateable2 }
      it { should_not include not_updateable1 }
      it { should_not include not_updateable2 }
      it { should_not include not_updateable3 }
    end

    describe '.displayable' do
      subject { Project.displayable tags }

      context "when supplying tags" do
        let(:tags) { "southeast, northwest" }

        it "should find tagged with tags" do
          scope = double
          Project.stub_chain(:enabled, :order) { scope }
          scope.should_receive(:tagged_with).with(tags, {:any => true})
          subject
        end

        context "when displayable projects are tagged" do
          before do
            projects(:socialitis).update_attributes(tag_list: tags)
            projects(:jenkins_project).update_attributes(tag_list: "southeast")
            projects(:pivots).update_attributes(tag_list: [])
          end

          it "should return scoped projects" do
            subject.should include(projects(:socialitis), projects(:jenkins_project))
            subject.should_not include projects(:pivots)
          end
        end

      end

      context "when not supplying tags" do
        let(:tags) { nil }

        it "should return scoped projects" do
          subject.should include projects(:pivots)
          subject.should include projects(:socialitis)
        end
      end

    end

    describe '.tagged' do
      subject { Project.tagged tags }

      context "when supplying tags" do
        let(:tags) { "southeast, northwest" }

        it "should find tagged with tags" do
          Project.should_receive(:tagged_with).with(tags, {:any => true})
          subject
        end

        context "when displayable projects are tagged" do
          before do
            projects(:socialitis).update_attributes(tag_list: tags)
            projects(:disabled).update_attributes(tag_list: tags)
            projects(:pivots).update_attributes(tag_list: [])
          end

          it "should return scoped projects" do
            subject.should include projects(:socialitis)
            subject.should include projects(:disabled)
            subject.should_not include projects(:pivots)
          end
        end
      end

      context "when not supplying tags" do
        let(:tags) { nil }

        it "should return scoped projects" do
          subject.should include projects(:pivots)
          subject.should include projects(:socialitis)
        end

        it "does not filter by enabled" do
          subject.should include projects(:disabled)
        end
      end
    end
  end

  describe "#code" do
    let(:project) { Project.new(name: "My Cool Project", code: code) }
    subject { project.code }

    context "code set but empty" do
      let(:code) { "" }
      it { should == "myco" }
    end

    context "code not set" do
      let(:code) { nil }
      it { should == "myco" }
    end

    context "code is set" do
      let(:code) { "code" }
      it { should == "code" }
    end
  end

  describe "#last green" do
    it "returns the successful project" do
      project = projects(:socialitis)
      project.statuses = []
      @happy_status = project.statuses.create!(success: true, build_id: 1)
      @sad_status = project.statuses.create!(success: false, build_id: 2)
      project.last_green.should == @happy_status
    end
  end

  describe "#status" do
    context "when project has statuses" do
      let(:project) { projects(:socialitis) }

      it "returns the most recent status" do
        project.status.should == project.recent_statuses.first
      end
    end

    context "when project has no statuses" do
      let(:project) { Project.new }

      it "returns new status" do
        project.status.new_record?.should be_true
      end

      it "returns new status associated with the project" do
        project.status.project.should == project
      end
    end
  end

  describe "tracker integration" do
    let(:project) { Project.new }

    describe "#tracker_project?" do
      it "should return true if the project has a tracker_project_id and a tracker_auth_token" do
        project.tracker_project_id = double(:tracker_project_id)
        project.tracker_auth_token = double(:tracker_auth_token)
        project.tracker_project?.should be(true)
      end

      it "should return false if the project has a blank tracker_project_id AND a blank tracker_auth_token" do
        project.tracker_project_id = ""
        project.tracker_auth_token = ""
        project.tracker_project?.should be(false)
      end

      it "should return false if the project doesn't have tracker_project_id" do
        project.tracker_project?.should be(false)
      end

      it "should return false if the project doesn't have tracker_auth_token" do
        project.tracker_project?.should be(false)
      end
    end
  end

  describe "#red?, #green? and #yellow?" do
    subject { project }

    context "the project has a failure status" do
      let(:project) { FactoryGirl.create(:jenkins_project, online: true) }
      let!(:status) { ProjectStatus.create!(project: project, success: false, build_id: 1) }

      its(:red?) { should be_true }
      its(:green?) { should be_false }
      its(:yellow?) { should be_false }
    end

    context "the project has a success status" do
      let(:project) { FactoryGirl.create(:project, online: true) }
      let!(:status) { ProjectStatus.create!(project: project, success: true, build_id: 1) }

      its(:red?) { should be_false }
      its(:green?) { should be_true }
      its(:yellow?) { should be_false }
    end

    context "the project has no statuses" do
      let(:project) { Project.new(online: true) }

      its(:red?) { should be_false }
      its(:green?) { should be_false }
      its(:yellow?) { should be_true }
    end

    context "the project is offline" do
      let(:project) { Project.new(online: false) }

      its(:red?) { should be_false }
      its(:green?) { should be_false }
      its(:yellow?) { should be_false }
    end
  end

  describe "#latest_status" do
    let(:project) { FactoryGirl.create :project, name: "my_project" }
    let!(:status) { project.statuses.create(success: true, build_id: 1) }

    it "returns the most recent status" do
      project.statuses.should_receive(:latest)
      project.latest_status
    end
  end

  describe "#red_since" do
    it "should return #published_at for the red status after the most recent green status" do
      project = projects(:socialitis)
      red_since = project.red_since

      2.times do |i|
        project.statuses.create!(success: false, build_id: i, :published_at => Time.now + (i+1)*5.minutes)
      end

      project = Project.find(project.id)
      project.red_since.should == red_since
    end

    it "should return nil if the project is currently green" do
      project = projects(:pivots)
      project.should be_green

      project.red_since.should be_nil
    end

    it "should return the published_at of the first recorded status if the project has never been green" do
      project = projects(:never_green)
      project.statuses.detect(&:success?).should be_nil
      project.red_since.should == project.statuses.last.published_at
    end

    it "should return nil if the project has no statuses" do
      project.statuses.should be_empty
      project.red_since.should be_nil
    end

    describe "#breaking build" do
      context "without any green builds" do
        it "should return the first red build" do
          project = projects(:socialitis)
          project.statuses.destroy_all
          first_red = project.statuses.create!(success: false, build_id: 1, published_at: 3.minutes.ago)
          project.statuses.create!(success: false, build_id: 2, published_at: 2.minutes.ago)
          project.statuses.create!(success: false, build_id: 3, published_at: 1.minutes.ago)
          project.breaking_build.should == first_red
        end
      end
    end
  end

  describe "#breaking build" do
    context "without any green builds" do
      it "should return the first red build" do
        project = projects(:socialitis)
        project.red_build_count.should == 1

        project.statuses.create!(success: false, build_id: 100)
        project.red_build_count.should == 2
      end
    end
  end

  describe "#red_build_count" do
    it "should return the number of red builds since the last green build" do
      project = projects(:socialitis)
      project.red_build_count.should == 1

      project.statuses.create(success: false, build_id: 100)
      project.red_build_count.should == 2
    end

    it "should return zero for a green project" do
      project = projects(:pivots)
      project.should be_green

      project.red_build_count.should == 0
    end

    it "should not blow up for a project that has never been green" do
      project = projects(:never_green)
      project.red_build_count.should == project.statuses.count
    end
  end

  describe "#enabled" do
    it "should be enabled by default" do
      project = Project.new
      project.should be_enabled
    end

    it "should store enabledness" do
      projects(:pivots).should be_enabled
      projects(:disabled).should_not be_enabled
    end
  end

  describe "#building?" do
    it "should be true if the project is currently building" do
      projects(:red_currently_building).should be_building
    end

    it "should return false for a project that is not currently building" do
      projects(:many_builds).should_not be_building
    end

    it "should return false for a project that has never been built" do
      projects(:never_built).should_not be_building
    end
  end

  describe "#has_auth?" do
    it "returns true if either username or password exists" do
      project.auth_username = "uname"
      project.has_auth?.should be_true

      project.auth_username = nil
      project.auth_password = "pwd"
      project.has_auth?.should be_true
    end

    it "returns false if both username and password are blank" do
      project.auth_username = ""
      project.auth_password = nil
      project.has_auth?.should be_false
    end
  end

  describe "#destroy" do
    it "should destroy related statuses" do
      project = projects(:pivots)
      project.statuses.count.should_not == 0
      status_id = project.statuses.first.id
      project.destroy
      proc { ProjectStatus.find(status_id)}.should raise_exception(ActiveRecord::RecordNotFound)
    end
  end

  describe "validation" do
    it "has a valid Factory" do
      FactoryGirl.build(:project).should be_valid
    end
  end

  describe '.project_specific_attributes' do
    subject { project_class.project_specific_attributes }

    context "when a CruiseControlProject" do
      let(:project_class) { CruiseControlProject }

      it { should =~ ['cruise_control_rss_feed_url'] }
    end

    context "when a JenkinsProject" do
      let(:project_class) { JenkinsProject }

      it { should =~ ['jenkins_base_url', 'jenkins_build_name'] }
    end

    context "when a TeamCityProject" do
      let(:project_class) { TeamCityProject }

      it { should =~ ['team_city_base_url', 'team_city_build_id'] }
    end

    context "when a TeamCityRestProject" do
      let(:project_class) { TeamCityRestProject }

      it { should =~ ['team_city_rest_base_url', 'team_city_rest_build_type_id'] }
    end

    context "when a TravisProject" do
      let(:project_class) { TravisProject }

      it { should =~ ['travis_github_account', 'travis_repository'] }
    end
  end

  describe "#has_status?" do
    subject { project.has_status?(status) }

    let(:project) { projects(:socialitis) }

    context "when the project has the status" do
      let!(:status) { project.statuses.create!(build_id: 99) }
      it { should be_true }
    end

    context "when the project does not have the status" do
      let!(:status) { ProjectStatus.create!(build_id: 99) }
      it { should be_false }
    end
  end

  describe '#current_build_url' do
    let(:project) { Project.new }
    subject { project.current_build_url }

    it { should be_nil }
  end

  describe "#generate_guid" do
    let(:project) { FactoryGirl.build(:project) }

    it "calls generate_guid" do
      project.should_receive :generate_guid
      project.save!
    end

    it "generates random GUID" do
      project.save!
      (project.guid).should_not be_nil
      (project.guid).should_not be_empty
    end
  end

  describe "#as_json" do
    context "build" do
      let(:project) { FactoryGirl.create(:project) }
      let(:status) { FactoryGirl.build(:project_status, published_at: 4.days.ago) }

      context "when there is no build history" do
        it "should have general build properties" do
          project.statuses << status
          hash = project.as_json

          hash["project_id"].should == project.id
          hash["build"]["code"].should == project.code
          hash["build"]["id"].should == project.id
          hash["build"]["status"].should == project.status_in_words
          hash["build"]["statuses"].should == [status]
          hash["build"]["published_at"].should == project.published_at
        end
      end

      context "when there is build history" do
        let(:older_status) { FactoryGirl.build(:project_status, success: true, published_at: 5.days.ago, build_id: 100) }
        let(:recent_status) { FactoryGirl.build(:project_status, success: false, published_at: 1.day.ago, build_id: 200) }
        before do
          project.statuses << older_status
          project.statuses << recent_status
          project.save
        end

        it "should have the statuses in the correct order" do
          statuses = project.as_json["build"]["statuses"]
          statuses.should == [recent_status, older_status]
        end
      end
    end

    context "tracker" do
      let(:project) { FactoryGirl.build(:project_with_tracker_integration) }

      it "should have a tracker properties" do
        hash = project.as_json

        hash["tracker"]["current_velocity"].should == project.current_velocity
        hash["tracker"]["variance"].should == project.variance
        hash["tracker"]["last_ten_velocities"].should == project.last_ten_velocities
        hash["tracker"]["stories_to_accept_count"].should == project.stories_to_accept_count
        hash["tracker"]["open_stories_count"].should == project.open_stories_count
      end
    end
  end

  describe "#status_in_words" do
    subject { project.status_in_words }

    let(:project) { FactoryGirl.build(:project) }
    let(:red) { false }
    let(:green) { false }
    let(:yellow) { false }

    before do
      project.stub(red?: red, green?: green, yellow?: yellow)
    end

    context "when project is red" do
      let(:red) { true }
      it { should == "failure" }
    end

    context "when project is green" do
      let(:green) { true }
      it { should == "success" }
    end

    context "when project is yellow" do
      let(:yellow) { true }
      it { should == "indeterminate" }
    end

    context "when project none of the statuses" do
      it { should == "offline" }
    end
  end

  describe "#variance" do
    context "when project has velocities" do
      let(:project) { FactoryGirl.create(:project_with_tracker_integration)}

      it "should return correct variance" do
        project.variance.should == 8
      end
    end

    context "when project has no velocities" do
      let(:project) { FactoryGirl.build(:project)}

      it "should return correct variance" do
        project.variance.should == 0
      end
    end
  end

  describe "#published_at" do
    subject { project.published_at }
    let(:project) { FactoryGirl.create(:project)}

    context "when there is a latest status" do
      let(:status) { FactoryGirl.build(:project_status, published_at: 5.days.ago) }
      before { project.statuses << status }

      it { should == status.published_at }
    end

    context "when there are no statuses" do
      it { should be_nil }
    end
  end
end
