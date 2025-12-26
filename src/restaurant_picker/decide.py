import random


def decide(restaurants, include=(), exclude=()):
    filtered_restaurants = []
    if include:
        for cuisine in include:
            cuisine_rest = [rest for rest in restaurants if cuisine in rest["tags"]]
            filtered_restaurants += cuisine_rest
    elif exclude:
        filtered_restaurants = []
        for cuisine in exclude:
            cuisine_rest = [rest for rest in restaurants if cuisine not in rest["tags"]]
            filtered_restaurants += cuisine_rest
    else:
        filtered_restaurants = restaurants

    result = random.choices(filtered_restaurants, weights=[rest["weight"] for rest in filtered_restaurants])
    if result:
        result = result[0]
    else:
        return

    return result["name"]


def available_tags(restaurants):
    return [rest["tags"] for rest in restaurants]
