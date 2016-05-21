struct Time
  # All times are stored in Redis as epoch floats.  The default
  # Float#to_s is terrible for this purpose so we need to roll
  # our own.
  def epoch_s
    "%.6f" % epoch_f
  end
end
