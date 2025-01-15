class Appointments::AddToCalendar < ApplicationService
  def initialize(appointment)
    @appointment = appointment
  end

  def call
    create_event

    self
  end

  def save_to_tmp_file
    tmp_file = Tempfile.new(['Massage', '.ics'])
    tmp_file.write(calendar.to_ical)
    tmp_file
  end

  private

  def create_event
    calendar.event do |event|
      dt = @appointment.slot_start
      event.uid         = @appointment.id.to_s
      event.dtstart     = Icalendar::Values::DateTime.new(dt)
      event.dtend       = Icalendar::Values::DateTime.new(dt + 1.hour)
      event.summary     = I18n.t('add_to_calendar.title')
      event.description = I18n.t('add_to_calendar.description', masseur: @appointment.masseur.name_with_sex_icon('left')).strip
      event.location    = I18n.t('add_to_calendar.location')
      event.url         = TelegramBotHelper.bot_url
      event.alarm do |a|
        a.action  = 'DISPLAY'
        a.trigger = '-PT1H' # 1 hour before
      end
    end
  end

  def calendar
    @calendar ||= Icalendar::Calendar.new
  end
end
