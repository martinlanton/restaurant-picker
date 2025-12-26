# Take-Out Decidator

A simple command-line tool to randomly choose restaurants based on cuisine preferences.

## Description

Can't decide where to order take-out from? This tool helps you make a decision by randomly selecting from your list of restaurants based on:
- **Weighted selection**: Favor certain restaurants by adjusting their weights
- **Include filters**: Only consider restaurants with specific cuisine tags
- **Exclude filters**: Avoid restaurants with certain cuisine tags

## Installation

Install the package using:
```bash
python setup.py install
```

Or for development:
```bash
pip install -e .
```

## Usage

### Basic Usage

Run the decision tool:
```bash
python -m restaurant_picker.run
```

### In Your Code

```python
from restaurant_picker.decide import decide
from restaurant_picker.restaurants import restaurants

# Random selection from all restaurants
result = decide(restaurants)
print(f"You should order from: {result}")

# Only include specific cuisines
result = decide(restaurants, include=["asian"])
print(f"Asian restaurant: {result}")

# Exclude certain cuisines
result = decide(restaurants, exclude=["meat", "chain"])
print(f"Non-meat, non-chain: {result}")
```

### Adding Restaurants

Edit `src/take_out_decidator/restaurants.py` to add your favorite restaurants:

```python
restaurants = [
    {"name": "your restaurant", "weight": 100, "tags": ["cuisine", "tag"]},
    # ... more restaurants
]
```

**Restaurant Structure**:
- `name`: Restaurant name (string)
- `weight`: Selection weight (higher = more likely to be chosen)
- `tags`: List of cuisine/category tags for filtering

## Running Tests

Run all tests:
```bash
pytest
```

Run tests with coverage:
```bash
pytest --cov=restaurant_picker
```

## License

See LICENSE file for details.
