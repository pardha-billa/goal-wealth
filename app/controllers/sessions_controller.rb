class SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :load_portfolio_links

  def new; end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password].to_s)
      session[:user_id] = user.id
      redirect_to home_path, notice: 'Signed in successfully.'
    else
      flash.now[:alert] = 'Invalid email or password.'
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path, notice: 'Signed out successfully.'
  end
end
