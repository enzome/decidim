# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Proposals
    describe PublishProposal do
      describe "call" do
        let(:component) { create(:proposal_component) }
        let(:organization) { component.organization }
        let!(:current_user) { create(:user, organization: organization) }
        let(:follower) { create(:user, organization: organization) }
        let(:proposal_draft) { create(:proposal, :draft, component: component, users: [current_user]) }
        let!(:follow) { create :follow, followable: current_user, user: follower }

        it "broadcasts ok" do
          expect { described_class.call(proposal_draft, current_user) }.to broadcast(:ok)
        end

        it "scores on the proposals badge" do
          expect { described_class.call(proposal_draft, current_user) }.to change {
            Decidim::Gamification.status_for(current_user, :proposals).score
          }.by(1)
        end

        it "broadcasts invalid when the proposal is from another author" do
          expect { described_class.call(proposal_draft, follower) }.to broadcast(:invalid)
        end

        it "traces the action", versioning: true do
          expect(Decidim.traceability)
            .to receive(:perform_action!)
            .with("publish", proposal_draft, current_user, visibility: "public-only")
            .and_call_original

          expect { described_class.call(proposal_draft, current_user) }.to change(Decidim::ActionLog, :count)

          action_log = Decidim::ActionLog.last
          expect(action_log.version).to be_present
          expect(action_log.version.event).to eq "update"
        end

        describe "events" do
          subject do
            described_class.new(proposal_draft, current_user)
          end

          it "notifies the proposal is published" do
            other_follower = create(:user, organization: organization)
            create(:follow, followable: component.participatory_space, user: follower)
            create(:follow, followable: component.participatory_space, user: other_follower)

            allow(Decidim::EventsManager).to receive(:publish)
              .with(hash_including(event: "decidim.events.gamification.badge_earned"))

            expect(Decidim::EventsManager)
              .to receive(:publish)
              .with(
                event: "decidim.events.proposals.proposal_published",
                event_class: Decidim::Proposals::PublishProposalEvent,
                resource: kind_of(Decidim::Proposals::Proposal),
                recipient_ids: [follower.id]
              )

            expect(Decidim::EventsManager)
              .to receive(:publish)
              .with(
                event: "decidim.events.proposals.proposal_published",
                event_class: Decidim::Proposals::PublishProposalEvent,
                resource: kind_of(Decidim::Proposals::Proposal),
                recipient_ids: [other_follower.id],
                extra: {
                  participatory_space: true
                }
              )

            subject.call
          end
        end
      end
    end
  end
end
