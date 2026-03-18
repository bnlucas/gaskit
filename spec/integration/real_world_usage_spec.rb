# frozen_string_literal: true

# Classes for testing real-world usage of Gaskit
class ProfileResult < Castkit::DataObject
  attribute :name, :string
  attribute :role, :string
end

# Classes for testing real-world usage of Gaskit
class ProfileOperation < Gaskit::Operation
  output_contract ProfileResult

  def call(user_id:)
    { name: "user-#{user_id}", role: "admin" }
  end
end

# Classes for testing real-world usage of Gaskit
class InvalidProfileOperation < Gaskit::Operation
  output_contract ProfileResult

  def call(user_id:)
    { name: "user-#{user_id}" } # missing role -> contract failure
  end
end

RSpec.describe "Real world usage" do
  it "runs a typed operation and validates output via Castkit" do
    result = ProfileOperation.call(user_id: 42, context: { request_id: "abc123" })

    expect(result).to be_success
    expect(result.value).to be_a(ProfileResult)
    expect(result.value.name).to eq("user-42")
    expect(result.value.role).to eq("admin")
    expect(result.error).to be_nil
    expect(result.context[:request_id]).to eq("abc123")
  end

  it "captures contract validation failures as operation failures" do
    result = InvalidProfileOperation.call(user_id: 42)

    expect(result).to be_failure
    expect(result.error).to be_a(Castkit::ContractError)
    expect(result.error.message).to include("Validation failed")
  end
end
