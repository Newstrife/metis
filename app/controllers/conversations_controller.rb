class ConversationsController < ApplicationController
  before_action :set_conversation, only: :show

  def index
    @conversations = current_user.conversations.recent
  end

  def new
    @conversation = current_user.conversations.new
  end

  def create
    @conversation = current_user.conversations.new(conversation_params)
    if @conversation.save
      redirect_to @conversation
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @messages = @conversation.messages.chronological
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end

  def conversation_params
    params.expect(conversation: %i[title backend])
  end
end
