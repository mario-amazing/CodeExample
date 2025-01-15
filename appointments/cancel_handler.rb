class Appointments::CancelHandler < ApplicationService
  include DateTimeHelper
  include XlsxSlotsHelper

  attr_reader :appointment

  def initialize(appointment_id, cancel_reason: nil)
    @appointment = Appointment.find(appointment_id)
    @cancel_reason = cancel_reason
  end

  def call
    return self if @appointment.slot_start <= DateTime.current || slot_cancelled?(slot_cell_current_text)

    update_slot_cell(text)
    @appointment.update!(cancel_reason: @cancel_reason || Appointment::DEFAULT_CANCEL_REASON)

    self
  end

  def self.cancel_prefix_text(cancel_reason = nil)
    "#{SLOT_SIGNS[:cancelled]}#{SLOT_SIGNS[:appointed_by_bot]}".tap { |text| text << "#{cancel_reason}, " if cancel_reason.present? }
  end

  private

  def text
    "#{self.class.cancel_prefix_text(@cancel_reason)}#{slot_cell_current_text}"
  end

  def api_spreadsheet
    @api_spreadsheet ||= ::Adapter::GoogleSheet.api_spreadsheet(@appointment.active_spreadsheet.sheet_id)
  end

  def api_worksheet
    @api_worksheet ||= api_spreadsheet.worksheet_by_title(date_to_sheet_name(@appointment.slot_start))
  end

  def update_slot_cell(value)
    api_worksheet[*@appointment.sheet_slot_cell] = value
    api_worksheet.save
  end

  def slot_cell_current_text
    @slot_cell_current_text ||= api_worksheet[*@appointment.sheet_slot_cell]
  end
end
