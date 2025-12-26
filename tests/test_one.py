from restaurant_picker import decide


def test_bluh():
    input_dict = {1: "bluh"}
    result = module_one.decide(input_dict)
    assert result == "bluh"


def test_foo():
    input_dict = {1: "foo"}
    result = module_one.decide(input_dict)
    assert result == "foo"
