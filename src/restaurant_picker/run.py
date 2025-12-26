if __name__ == '__main__':
    from restaurant_picker.decide import decide
    from restaurant_picker.restaurants import restaurants

    result = decide(restaurants, exclude=["meat"])
    print(result)
