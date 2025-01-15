class Appointments::UpdateHandler < Appointments::CreateHandler
  def initialize(appointment_id, appointment_params)
    @appointment_id = appointment_id
    super(appointment_params)
  end

  def call
    @slot_text = api_worksheet[*appointment_slot_cell]

    update_slot_cell(final_text)
    save_appointment

    self
  end

  def appointment
    @appointment ||= begin
      appointment = Appointment.find(@appointment_id)
      appointment.attributes = @appointment_params
      appointment
    end
  end
end
