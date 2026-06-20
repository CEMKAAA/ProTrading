The idea
“Never disdain to make a verification when opportunity offers.” Henri Poincaré.

I always loved this quote from Poincaré. It's a classical version of the "trust but verify" famous Russian proverb. If there is an area where it is imperative to apply this principle, it is in quantitative trading.

With that in mind, I decided to test a mean reversion strategy I read in a blog. The original rules were clear:

Compute the rolling mean of High minus Low over the last 25 days;

Compute the IBS indicator: (Close - Low) / (High - Low);

Compute a lower band as the rolling High over the last 10 days minus 2.5 x the rolling mean of High mins Low (first bullet);

Go long whenever SPY closes under the lower band (3rd bullet), and IBS is lower than 0.3;

Close the trade whenever the SPY close is higher than yesterday's high.

The logic behind this trading strategy is that the market tends to bounce back once it drops too low from its recent highs.

The blog showed an impressive equity curve. My first thought was about Poincaré: this is an opportunity to make a verification that I won't disdain.

First experiments
Running the original rules precisely as described in the blog led to slightly worse results: 1.39 Sharpe, 7.1% annual return from 1993–2024 (vs. 8.3% Buy&Hold), despite being invested only 18% of the time. That can be explained by my backtest being almost four years longer (the original run was only until 2020).

Then, after trying some instruments, I experimented with QQQ and got much better results:




Equity and drawdown curves for the strategy with original rules applied to QQQ
The summary of backtest statistics showed promising results:




Summary of the backtest statistics



Summary of the backtest trades
Although those were good results, the maximum drawdown was too long and too deep for my taste. Holding to a strategy through a ~25% drawdown and having a drawdown of one and a half years is too much for most people's risk tolerance.

What could we do to try to minimize this drawdown?

Type your email...
Subscribe
Improvement 1: Market Regime Filter
At first, I tried to apply stop-losses. But they never quite worked. Whenever I used them, they would not only cut losers but also cut winners, making things worse.

Then, I tried Market Regime Filters, which are great tools for reducing drawdowns. Implementing a market regime filter is quite simple. I just needed to add a trading rule that would only allow trades in bull markets and get to 100% cash in bear markets.

There are several ways to define a bull/bear market quantitatively. I decided to use the simplest one:

Whenever the prices are above the 200-SMA, we are in a bull market: we can trade;

Whenever the prices fall below the 200-SMA, we are in a bear market: we move to 100% cash.

I experimented a bit with the number of days in the SMA — 150, 200, 300 — to find what works best. After tweaking a bit, I found that 300 was the best option. But I tried 4-5 options only (I'm not a fan of optimization; I believe they can quickly lead to overfitting).

The results are shown below:




Equity and drawdown curves for the strategy with market regime filter



Summary of the backtest statistics



Summary of the backtest trades
It worked! This was a significant improvement over the original rules but with some drawbacks:

The Sharpe Ratio went from 1.83 to 2.25, driven by a significant reduction in exposure time: the strategy spent 11.7% of the time invested vs. 20.0% in the previous experiment;

The drawdown improved drastically: the maximum drawdown went from -24.7% to -11.7%, the average drawdown went from -2.8% to -2.1%, and the # of drawdowns went from 7/year to 4/year;

However, the total return was almost cut by half: the annualized returns went from 14.6% to 7.4%.

Could we improve even further? Could we change it to re-introduce more returns without compromising on more drawdowns?

Type your email...
Subscribe
Improvement 2: A better exit strategy with dynamic stop losses
My first idea was to use leverage. So, I tested the exact same strategy with the following adjustments:

Whenever the strategy signaled to go long, it would go long on QLD instead of QQQ (2x leverage);

Then, the strategy would observe QLD prices to exit instead of QQQ.

This idea did not work. Although the strategy achieved 11.7% in annualized returns with a 2.1 Sharpe, it failed to keep the maximum drawdown in check: the maximum drawdown reached -29%, worse even than our very first experiment. So, I gave up on using leverage.

Then, I decided to abandon the market regime filter but improve the exit strategy. Curiously, the market regime filter was what inspired me to try a new exit strategy. Now, the strategy would exit trades whenever one of the two conditions below were met:

Close the trade whenever the price is higher than yesterday's high (same as before);

Close the trade whenever the price is lower than the 300-SMA (new condition).

We could see this new condition as a dynamic stop loss. Anyway, here are the results:




Equity and drawdown curves for the strategy with original rules applied to QQQ with a dynamic stop



Summary of the backtest statistics



Summary of the backtest trades
There we go! In this experiment, we improved our first run, reintroducing a higher return while reducing the drawdown. Specifically:

The Sharpe Ratio went from the original 1.83 to 2.11, while the annualized returns from 14.6% to 13.0%, still well above Buy&Hold (9.2%);

The maximum drawdown went from -24.7% to -20.3%;

Most importantly, the maximum drawdown duration went from 535 days to less than a year, and the # of drawdowns from 177 to 155.

While this maximum drawdown is still a bit high for my taste, this is a strategy I would be willing to forward-test and trade.

However, I still thought I could do better.

Improvement 3: Long & Short
Yesterday, I went for a morning run. Somehow, getting in a workout sparks my creativity. By the end of 10K, I got the idea: what if the strategy simultaneously traded QQQ in bull markets and PSQ (the inverse ETF) in bear markets?

This is the answer:




Equity and drawdown curves for the strategy applied to QQQ in bull markets and PSQ in bear markets



Summary of the backtest statistics



Summary of the backtest trades
We were able to achieve a good compromise with this last improvement:

While the 2.02 Sharpe was lower than the 2.25 from the Market Regime Filter experiment, the Long&Short experiment improved the annualized return from 7.4% to 8.9%, almost the same as the Buy&Hold (9.2%): the additional trades in bear markets paid off;

Comparing the maximum drawdown to the Market Regime Filter experiment, it went from -11.7% to -13.3%, a slight increase; however, compared to the Dynamic Stop Losses experiment (-20.3%), it was a drastic reduction.

Final Thoughts
Which experiment should we choose to trade? The one with Dynamic Stop Losses, with a higher Sharpe (2.11), higher annualized returns (13.0%), and lower maximum drawdown (-20.3%)? Or should we choose the Long&Short variation, with a lower Sharpe (2.02), lower annualized returns (8.9%), but a much better maximum drawdown (-13.3%)?

Also, taking into consideration the low exposure time from 12-15% in all experiment improvements, should we even consider the Market Regime Filter long-only experiment with the highest Sharpe (2.25) and lowest maximum drawdown (-11.7%) and complement it with different strategies to increase its low annualized returns (7.4%)?

Those are good questions. If I had to pick one, I would choose the Long&Short variation. But the experiment with Dynamic Stop Losses also has its merits.

However, I believe the best way forward would be to develop new complementary strategies and run them simultaneously to increase the exposure time, thus increasing the total return. Think about the Market Regime Filter long-only experiment:

It achieved a 2.25 Sharpe, annualized returns of 7.4%, and -11.7% maximum drawdown with only 11.7% of exposure time;

If we could be invested in this strategy 100% of the time, theoretically, we could achieve 63.7% of annual returns;

So, let's say we could develop additional strategies with the same stats and combine them such that we could increase the time invested to 50% (more realistically): we could reach close to 32% annual returns with a 2.25 Sharpe and drawdowns lower than -12%!

I will do this (while all three variations get a good forward test in real market conditions).

I'd love to hear your thoughts about this approach. If you have any questions or comments, just reach out via Twitter or email.

Also, if you want to implement this strategy and need help, just let me know.

Cheers!

Quantitativo