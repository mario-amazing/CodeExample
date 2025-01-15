class Appointments::Manager::CreateHandler < Appointments::CreateHandler
  private

  def could_be_appointed?
    appointment.slot_start > DateTime.current + FreeSlot::MASSEUR_TIME_RETENTION && (slot_free?(ws_slot_text) || slot_reserved?(ws_slot_text))
  end

  def ws_slot_text
    @ws_slot_text ||= api_worksheet[*appointment_slot_cell]&.delete(XlsxSlotsHelper::SLOT_SIGNS[:reserved])
  end
end
