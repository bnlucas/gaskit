# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit::Repository do
  let(:model_class) do
    Class.new do
      def self.find(id)
        "found #{id}"
      end

      def self.where(**)
        "where called"
      end
    end
  end

  def build_repo_with_model(model = model_class)
    Class.new(Gaskit::Repository).tap { |repo| repo.model(model) }
  end

  describe "instantiation" do
    it "raises an error if instantiated directly" do
      repo_class = build_repo_with_model
      expect { repo_class.new }.to raise_error(TypeError, /Repositories cannot be instantiated/)
    end
  end

  describe ".model" do
    it "returns the model after assignment" do
      repo_class = build_repo_with_model
      expect(repo_class.model).to eq(model_class)
    end

    it "raises if setting model twice" do
      repo_class = Class.new(Gaskit::Repository)
      repo_class.model(model_class)

      expect do
        repo_class.model(Class.new)
      end.to raise_error(/already has a model set/)
    end
  end

  describe "delegated methods" do
    it "forwards common ActiveRecord methods to the model" do
      repo_class = build_repo_with_model
      expect(repo_class.find(1)).to eq("found 1")
      expect(repo_class.where(name: "Test")).to eq("where called")
    end

    it "raises NoMethodError for methods not delegated or defined" do
      repo_class = build_repo_with_model
      expect { repo_class.foobar }.to raise_error(NoMethodError)
    end
  end

  describe "rls scope" do
    let(:scoped_relation_class) do
      Class.new do
        def initialize(context)
          @context = context
        end

        def where(**)
          "scoped #{@context}"
        end
      end
    end

    it "defaults to the model when no scope is defined" do
      repo_class = build_repo_with_model
      expect(repo_class.base_relation).to eq(model_class)
    end

    it "applies the rls scope to delegated queries" do
      repo_class = build_repo_with_model
      repo_class.rls_scope { |_context| scoped_relation_class.new("tenant-1") }

      expect(repo_class.where(name: "Test")).to eq("scoped tenant-1")
    end

    it "passes context to the scope block" do
      repo_class = build_repo_with_model
      repo_class.rls_scope { |context| scoped_relation_class.new(context) }

      expect(repo_class.where(context: "tenant-2")).to eq("scoped tenant-2")
      expect(repo_class.with_context("tenant-3").where).to eq("scoped tenant-3")
    end
  end

  describe ".log_execution_time" do
    let(:repo_class) { build_repo_with_model }

    it "logs and returns the result" do
      expect(repo_class.logger).to receive(:log).with(
        :debug,
        /completed/,
        context: hash_including(:duration)
      )

      result = repo_class.log_execution_time { 42 }
      expect(result).to eq(42)
    end

    it "logs errors and re-raises them" do
      expect(repo_class.logger).to receive(:error).with(
        /failed/,
        context: hash_including(:duration, :error)
      )

      expect do
        repo_class.log_execution_time { raise "boom" }
      end.to raise_error("boom")
    end
  end
end
