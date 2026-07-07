import logging
from luma.core.interface.serial import noop, spi
from luma.core.render import canvas
from luma.core.virtual import viewport
from luma.led_matrix.device import max7219
from luma.core.legacy import show_message
from luma.core.legacy.font import proportional, LCD_FONT


def create_device(display_config: dict):
    serial = spi(port=0, device=0, gpio=noop())
    device = max7219(
        serial,
        cascaded=display_config.get("cascaded", 1),
        block_orientation=display_config.get("block_orientation", 0),
        rotate=display_config.get("rotate", 0),
        blocks_arranged_in_reverse_order=display_config.get("reverse_order", False),
    )
    device.contrast(display_config.get("contrast", 5))
    return device


def show_startup_message(device, message: str, scroll_delay: float):
    logging.info("Showing startup message")
    show_message(device, message, fill="white", font=proportional(LCD_FONT), scroll_delay=scroll_delay)


def show_text(device, message: str, scroll_delay: float):
    with canvas(device) as draw:
        show_message(device, message, fill="white", font=proportional(LCD_FONT), scroll_delay=scroll_delay)
