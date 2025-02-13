class Users::PasswordsController < Devise::PasswordsController
  include ApplicationHelper
  include PhoneNumberHelper
  include SmsBodyHelper

  def create
    email, phone_number = [params[resource_name][:email], params[resource_name][:phone_number]]
    @resource = email.blank? ? User.find_by(phone_number: phone_number) : User.find_by(email: email)

    # re-render and display any errors
    params_is_valid, error_resource = password_params_is_valid(resource, email, phone_number)
    if !params_is_valid
      respond_with(error_resource)
      return
    end

    # generate a reset token and
    # call devise mailer
    reset_token = send_email_reset(email)
    # for case where user enters ONLY a phone number, generate a new reset token to use;
    # otherwise, use the same reset token as sent by devise mailer
    send_sms_reset(@resource, phone_number, reset_token)
    redirect_to after_sending_reset_password_instructions_path_for(resource_name), notice: "You will receive an email or SMS with instructions on how to reset your password in a few minutes."
  end

  private

  def send_email_reset(email)
    reset_token = nil
    if !email.blank?
      reset_token = @resource.send_reset_password_instructions
    end
    reset_token
  end

  def send_sms_reset(resource, phone_number, reset_token)
    if !phone_number.blank?
      reset_token ||= resource.generate_password_reset_token
      short_io_service = ShortUrlService.new
      short_io_service.create_short_url(request.base_url + "/users/password/edit?reset_password_token=#{reset_token}")
      twilio_service = TwilioService.new(resource.casa_org.twilio_api_key_sid, resource.casa_org.twilio_api_key_secret, resource.casa_org.twilio_account_sid)
      sms_params = {
        From: resource.casa_org.twilio_phone_number,
        Body: password_reset_msg(resource.display_name, short_io_service.short_url),
        To: phone_number
      }
      twilio_service.send_sms(sms_params)
    end
  end

  def password_params_is_valid(resource, email, phone_number)
    if email.blank? && phone_number.blank?
      resource.errors.add(:base, "Please enter at least one field.")
      return [false, resource]
    end

    phone_number_is_valid, error_message = valid_phone_number(phone_number)
    if !phone_number_is_valid
      resource.errors.add(:phone_number, error_message)
      return [false, resource]
    end

    if resource.email != email || resource.phone_number != phone_number
      # A new, empty resource is returned (see application helper)
      # so to check for nil, we need to check its email/phone fields
      resource.errors.add(:base, "User does not exist.")
      return [false, resource]
    end
    [true, nil]
  end
end
