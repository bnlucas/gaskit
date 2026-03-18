# frozen_string_literal: true

require "gaskit/flow_result"

RSpec.describe Gaskit::FlowResult do
  it "includes steps in the hash representation" do
    result = described_class.new(true, "ok", nil, steps: [{ step: 1 }], duration: "0.000001", context: {})

    expect(result.to_h[:steps]).to eq([{ step: 1 }])
  end
end
