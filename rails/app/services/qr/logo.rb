require "chunky_png"

module Qr
  module Logo
    MAX_BYTES = 500.kilobytes
    def self.read(upload)
      raise ArgumentError, "Выберите логотип в формате PNG" unless upload.respond_to?(:read)
      bytes = upload.read(MAX_BYTES + 1)
      raise ArgumentError, "PNG должен быть не больше 500 КБ" if bytes.bytesize > MAX_BYTES
      unless bytes.start_with?("\x89PNG\r\n\x1a\n".b) && bytes.bytesize >= 24 && bytes.byteslice(12, 4) == "IHDR"
        raise ArgumentError, "Выберите корректный PNG-файл"
      end
      width, height = bytes.byteslice(16, 8).unpack("NN")
      raise ArgumentError, "Размер логотипа должен быть от 1 до 2000 пикселей по каждой стороне" unless [width, height].all? { |size| (1..2000).cover?(size) }
      image = ChunkyPNG::Image.from_blob(bytes)
      image.to_blob
    rescue ChunkyPNG::Exception
      raise ArgumentError, "Не удалось прочитать PNG-файл"
    end
  end
end
