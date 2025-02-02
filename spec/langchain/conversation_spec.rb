# frozen_string_literal: true

RSpec.describe Langchain::Conversation do
  let(:llm) { double("Langchain::LLM::OpenaAI") }

  subject { described_class.new(llm: llm) }

  describe "#set_context" do
    let(:context) { "You are a chatbot" }

    it "sets the context" do
      subject.set_context(context)

      expect(subject.context).to eq(context)
    end
  end

  describe "#add_examples" do
    let(:examples1) { [{role: "user", content: "Hello"}, {role: "ai", content: "Hi"}] }
    let(:examples2) { [{role: "user", content: "How are you doing?"}, {role: "ai", content: "I'm doing well. How about you?"}] }

    it "adds examples" do
      subject.add_examples(examples1)

      expect(subject.instance_variable_get(:@examples)).to eq(examples1)

      subject.add_examples(examples2)
      expect(subject.instance_variable_get(:@examples)).to eq(examples1 | examples2)
    end
  end

  describe "#message" do
    let(:context) { "You are a chatbot" }
    let(:examples) { [{role: "user", content: "Hello"}, {role: "ai", content: "Hi"}] }
    let(:prompt) { "How are you doing?" }
    let(:response) { "I'm doing well. How about you?" }

    context "with stream: true option and block passed in" do
      let(:block) { proc { |chunk| print(chunk) } }
      let(:conversation) { described_class.new(llm: llm, &block) }

      it "messages the model and yields the response" do
        expect(llm).to receive(:chat).with(
          context: nil,
          examples: [],
          messages: [{role: "user", content: prompt}],
          &block
        ).and_return(response)

        expect(conversation.message(prompt)).to eq(response)
      end
    end

    context "with simple prompt" do
      it "messages the model and returns the response" do
        expect(llm).to receive(:chat).with(
          context: nil,
          examples: [],
          messages: [{role: "user", content: prompt}]
        ).and_return(response)

        expect(subject.message(prompt)).to eq(response)
      end
    end

    context "with context" do
      before do
        subject.set_context(context)
      end

      it "messages the model and returns the response" do
        expect(llm).to receive(:chat).with(
          context: context,
          examples: [],
          messages: [{role: "user", content: prompt}]
        ).and_return(response)

        expect(subject.message(prompt)).to eq(response)
      end
    end

    context "with context and examples" do
      before do
        subject.set_context(context)
        subject.add_examples(examples)
      end

      it "messages the model and returns the response" do
        expect(llm).to receive(:chat).with(
          context: context,
          examples: [
            {role: "user", content: "Hello"},
            {role: "ai", content: "Hi"}
          ],
          messages: [
            {role: "user", content: prompt}
          ]
        ).and_return(response)

        expect(subject.message(prompt)).to eq(response)
      end
    end

    context "with options" do
      subject { described_class.new(llm: llm, temperature: 0.7) }

      it "messages the model with passed options" do
        expect(llm).to receive(:chat).with(
          context: nil,
          examples: [],
          messages: [{role: "user", content: prompt}],
          temperature: 0.7
        ).and_return(response)

        expect(subject.message(prompt)).to eq(response)
      end
    end

    context "with length limit exceeded" do
      let(:messages) { [] }

      subject { described_class.new(llm: llm, messages: messages) }

      before do
        allow(llm).to receive(:client).and_return(client)
        allow(client).to receive(:chat).and_return(response)
      end

      context "with OpenAI LLM" do
        let(:llm) { Langchain::LLM::OpenAI.new api_key: "TEST" }
        let(:client) { double("OpenAI::Client") }

        context "a single prompt that exceeds the token limit" do
          let(:prompt) { "Lorem " * 4096 }

          it "raises an error" do
            expect { subject.message(prompt) }.to raise_error(Langchain::Utils::TokenLength::TokenLimitExceeded)
          end
        end

        context "message history exceeds the token limit" do
          let(:prompt) { "Lorem " * 2048 }
          let(:response) do
            {"choices" => [{"message" => {"content" => "I'm doing well. How about you?"}}]}
          end
          let(:context) { "You are a chatbot" }
          let(:examples) { [{role: "user", content: "Hello"}, {role: "ai", content: "Hi"}] }
          let(:messages) do
            [
              {role: "user", content: "Lorem " * 512},
              {role: "ai", content: "Ipsum " * 512},
              {role: "user", content: "Dolor " * 512},
              {role: "ai", content: "Sit " * 512}
            ]
          end

          before do
            subject.set_context(context)
            subject.add_examples(examples)
          end

          it "should drop 2 first messages and call an API" do
            expect(client).to receive(:chat).with(
              parameters: {
                max_tokens: 457,
                messages: [
                  {role: "system", content: "You are a chatbot"},
                  {role: "user", content: "Hello"},
                  {role: "assistant", content: "Hi"},
                  {role: "user", content: messages[2][:content]},
                  {role: "assistant", content: messages[3][:content]},
                  {role: "user", content: prompt}
                ],
                model: "gpt-3.5-turbo",
                temperature: 0.0
              }
            ).and_return(response)

            expect(subject.message(prompt)).to eq("I'm doing well. How about you?")
          end
        end
      end

      context "with PaLM2 LLM" do
        let(:llm) { Langchain::LLM::GooglePalm.new api_key: "TEST" }
        let(:client) { double("GooglePalmApi::Client") }

        before do
          allow(client).to receive(:generate_chat_message).and_return(response)
          allow(client).to receive(:count_message_tokens) do |value|
            {"tokenCount" => value[:prompt].count(" ")}
          end
        end

        context "a single prompt that exceeds the token limit" do
          let(:prompt) { "Lorem " * 4096 }

          it "raises an error" do
            expect { subject.message(prompt) }.to raise_error(Langchain::Utils::TokenLength::TokenLimitExceeded)
          end
        end

        context "message history exceeds the token limit" do
          let(:prompt) { "Lorem " * 2048 }
          let(:response) do
            {"candidates" => [{"content" => "I'm doing well. How about you?"}]}
          end
          let(:context) { "You are a chatbot" }
          let(:examples) { [{role: "user", content: "Hello"}, {role: "ai", content: "Hi"}] }
          let(:messages) do
            [
              {role: "user", content: "Lorem " * 512},
              {role: "ai", content: "Ipsum " * 512},
              {role: "user", content: "Dolor " * 512},
              {role: "ai", content: "Sit " * 512}
            ]
          end

          before do
            subject.set_context(context)
            subject.add_examples(examples)
          end

          it "should drop 2 first messages and call an API" do
            expect(client).to receive(:generate_chat_message).with(
              context: "You are a chatbot",
              examples: [
                {input: {content: "Hello"}, output: {content: "Hi"}}
              ],
              messages: [
                {author: "ai", content: messages[1][:content]},
                {author: "user", content: messages[2][:content]},
                {author: "ai", content: messages[3][:content]},
                {author: "user", content: prompt}
              ],
              temperature: 0.0,
              chat_completion_model_name: "chat-bison-001"
            ).and_return(response)

            expect(subject.message(prompt)).to eq("I'm doing well. How about you?")
          end
        end
      end
    end
  end
end
