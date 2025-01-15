class Appointments::CreateHandler < ApplicationService
  include CouponHelper
  include XlsxSlotsHelper
  include DateTimeHelper

  STATUSES = {
    success: :success,
    failure: :failure,
    slot_busy: :slot_busy
  }.freeze

  attr_reader :status

  def initialize(appointment_params)
    @status = STATUSES[:success]
    @appointment_params = appointment_params&.with_indifferent_access
  end

  def call
    unless could_be_appointed?
      @status = STATUSES[:slot_busy]
      return self
    end

    update_slot_cell(slot_final_text)
    save_appointment

    return self if @status == STATUSES[:failure]

    notify_admin_new_appointment
    notify_masseur_new_google_appointment
    schedule_notify_review

    self
  end

  def cert_counts_info_text
    @cert_counts_info_text ||= cert_counts_info(appointment.coupon).slice('done', 'appointed', 'max').tap { |counts_info| counts_info['appointed'] += 1 }.values.join('/')
  end

  def appointment
    @appointment ||= Appointment.new(@appointment_params)
  end

  def slot_new_text
    return appointment.custom_slot_text if appointment.custom_slot_text.present?

    slot_new_text = appointment.slot_text
    if appointment.certificate?
      update_appointments_info
      slot_new_text << " [#{cert_counts_info_text}]"
    end
    slot_new_text
  end

  private

  def could_be_appointed?
    appointment.slot_start > DateTime.current + FreeSlot::MASSEUR_TIME_RETENTION && slot_free?(ws_slot_text)
  end

  def slot_final_text
    @slot_final_text ||= begin
      slot_final_text = slot_new_text
      slot_final_text << "\n\n#{ws_slot_text}" if ws_slot_text.present?
      slot_final_text
    end
  end

  def ws_slot_text
    @ws_slot_text ||= api_worksheet[*appointment_slot_cell]
  end

  def sheet_name
    @sheet_name ||= date_to_sheet_name(appointment.slot_start)
  end

  def spreadsheet
    @spreadsheet ||= Spreadsheet.find_by(masseur_id: appointment.masseur_id, active: true)
  end

  def worksheet
    @worksheet ||= Worksheet.find_by(spreadsheet: spreadsheet, name: sheet_name)
  end

  def api_spreadsheet
    @api_spreadsheet ||= ::Adapter::GoogleSheet.api_spreadsheet(spreadsheet.sheet_id)
  end

  def api_worksheet
    @api_worksheet ||= api_spreadsheet.worksheet_by_title(sheet_name)
  end

  def update_slot_cell(value)
    api_worksheet[*appointment_slot_cell] = value
    api_worksheet.save
  end

  def update_appointments_info
    Xlsx::AppointmentSlots::Upserter.call
  end

  def save_appointment
    ActiveRecord::Base.transaction do
      appointment.save!
      GoogleAppointment
        .find_or_initialize_by(slot_start: google_appointment_params['slot_start'])
        .tap { |ga| ga.update(google_appointment_params.merge(slot_data: slot_final_text, status: :upcoming)) }
      FreeSlot.delete_by(worksheet: worksheet, slot_cell: appointment_slot_cell)
    rescue ActiveRecord::Rollback => e
      Rails.logger.error e
      @status = STATUSES[:failure]
      update_slot_cell(ws_slot_text)
      User.admins.first&.notify_telegram_user(text: e.to_s)
      raise e
    end
  end

  def appointment_slot_cell
    @appointment_slot_cell ||= appointment.sheet_slot_cell
  end

  def schedule_notify_review
    AfterMassageGetReviewJob.perform_at(appointment.slot_start + 65.minutes, appointment.id) if appointment.id.present?
  end

  def google_appointment_params
    @appointment_params.slice(*GoogleAppointment.attribute_names)
  end

  def notify_admin_new_appointment
    Notifications::Manager::NewAppointmentJob.perform_async(appointment.id) if appointment.id.present?
  end

  def notify_masseur_new_google_appointment
    Notifications::Masseur::NewGoogleAppointmentJob.perform_async(appointment.google_appointment.id) if appointment.google_appointment.present?
  end
end
